# claude-p-gateway

Minimal Anthropic-compatible HTTP gateway that proxies requests to a locally-authenticated `claude -p`. Lets other tools call your Claude Code CLI (authenticated with a Claude.ai subscription) over the network without consuming API credits.

## Stack

- Bun + Hono
- Shells out to `claude -p --output-format json`
- Bearer-token auth at the gateway boundary

## Setup

```sh
bun install
cp .env.example .env
# edit .env, set a long random GATEWAY_TOKEN
bun run dev
```

Smoke test:

```sh
curl -s http://localhost:8787/v1/messages \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"say hi in five words"}]}'
```

## VPS deploy

1. Install Claude Code on the VPS: `curl -fsSL https://claude.ai/install.sh | bash`
2. Authenticate locally (`claude` → `/login` → pick your Claude.ai subscription account)
3. Copy auth state from laptop to VPS:
   ```sh
   scp ~/.claude/.credentials.json vps:~/.claude/.credentials.json
   scp ~/.claude.json vps:~/.claude.json
   ```
4. On the VPS, verify with `claude -p "hello"` before starting the gateway.
5. Run as a service (systemd unit or `pm2`); proxy via Caddy/Nginx for TLS.

## Endpoints

- `GET /health` — unauthenticated liveness
- `POST /v1/messages` — Anthropic-shaped request, returns Anthropic-shaped response

## Caveats

- Subscription rate limits still apply (5-hour windows on Max).
- Using a Claude.ai subscription as a backend for unrelated services may violate Anthropic's ToS. Intended for personal automations only.
- No streaming yet. Add `--output-format stream-json` and SSE when needed.
