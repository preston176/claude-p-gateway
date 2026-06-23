# Deploying claude-p-gateway

VPS rollout for a single-user, personal-use deploy. Assumes a Debian or Ubuntu host with `systemd` and a working `caddy` install.

## 0. Provision a service user

```sh
sudo useradd --system --create-home --home-dir /var/lib/gateway --shell /usr/sbin/nologin gateway
sudo install -d -o gateway -g gateway -m 750 /opt/claude-p-gateway
sudo install -d -o root   -g root   -m 755 /etc/claude-p-gateway
```

## 1. Install Erlang/OTP, Elixir, and the `claude` CLI on the VPS

Use `asdf`, `mise`, or distro packages, whichever you already use. Then:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

## 2. Copy Claude.ai subscription credentials onto the VPS

On your **laptop** (where you've already done `claude` → `/login` against your Claude.ai account):

```sh
scp ~/.claude/.credentials.json vps:/tmp/credentials.json
scp ~/.claude.json              vps:/tmp/claude.json
```

On the **VPS**:

```sh
sudo install -o gateway -g gateway -m 600 /tmp/credentials.json /var/lib/gateway/.claude/.credentials.json
sudo install -o gateway -g gateway -m 600 /tmp/claude.json      /var/lib/gateway/.claude.json
sudo -u gateway claude -p "hello"   # sanity check
```

## 3. Build a release

On a build host with the same OS/arch as the VPS (or on the VPS itself):

```sh
git clone https://github.com/preston176/claude-p-gateway.git
cd claude-p-gateway
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix release
```

Copy `_build/prod/rel/claude_p_gateway/` to `/opt/claude-p-gateway/` on the VPS, preserving permissions:

```sh
rsync -a --delete _build/prod/rel/claude_p_gateway/ vps:/opt/claude-p-gateway/
sudo chown -R gateway:gateway /opt/claude-p-gateway
```

## 4. Configure systemd

```sh
sudo install -m 644 deploy/systemd/claude-p-gateway.service /etc/systemd/system/
sudo install -m 600 -o root -g gateway deploy/systemd/env.example /etc/claude-p-gateway/env
# Edit /etc/claude-p-gateway/env: set SECRET_KEY_BASE, GATEWAY_TOKEN, PHX_HOST.
#   mix phx.gen.secret 64   # for SECRET_KEY_BASE
#   openssl rand -hex 32    # for GATEWAY_TOKEN
sudo systemctl daemon-reload
sudo systemctl enable --now claude-p-gateway
sudo systemctl status claude-p-gateway
```

Smoke test it locally on the VPS:

```sh
curl -s http://127.0.0.1:4000/health
curl -s http://127.0.0.1:4000/v1/messages \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hi"}]}'
```

## 5. Front with Caddy for TLS

```sh
sudo cp deploy/caddy/Caddyfile.example /etc/caddy/Caddyfile
# Edit: replace gateway.example.com with your real host.
sudo systemctl reload caddy
```

DNS: point `gateway.example.com` A/AAAA at the VPS first; Caddy will obtain a cert on next request.

## 6. (Optional) Enable the admin pages

Set `DASHBOARD_USER` and `DASHBOARD_PASS` in `/etc/claude-p-gateway/env` and `systemctl restart claude-p-gateway`. Two routes become available behind that BasicAuth:

- `https://gateway.example.com/admin/settings` for rotating the gateway token and tuning the rate limit at runtime.
- `https://gateway.example.com/admin/dashboard` for the Phoenix LiveDashboard.

Without the env vars set, both routes return 404. Make sure `STATE_PATH` is also set if you want changes from the settings page to survive restarts.

## Operating tips

- `journalctl -u claude-p-gateway -f` to tail logs.
- `sudo systemctl restart claude-p-gateway` after editing the env file (changes to `/etc/claude-p-gateway/env` are only loaded on start).
- The `claude` CLI may rotate OAuth tokens. If calls start failing with auth errors, re-run `claude` interactively on your laptop and re-copy `~/.claude/.credentials.json` to the VPS.
- Subscription rate limits still apply. The built-in token bucket at `/admin/settings` clips concurrent calls before they hit Anthropic, but if you start hitting Claude's own 5-hour windows the gateway has no awareness of it. Lower the bucket capacity to throttle yourself further.
- Setting `STATE_PATH=/var/lib/gateway/state.json` is strongly recommended so that any rate-limit or token changes made from `/admin/settings` survive restarts. Without it the values revert to whatever's in the env file on every boot.
