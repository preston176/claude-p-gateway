# claude-p-gateway

Self-hosted, Anthropic-compatible HTTP gateway that proxies `/v1/messages` to a locally-authenticated `claude -p`. Lets a Claude.ai subscription back your personal tooling instead of metered API credits.

Built on Phoenix (API-only) + Bandit, with each subprocess invocation supervised under a `Task.Supervisor` so a stuck or crashing `claude` call cannot take the gateway down.

> **Previous Bun + Hono implementation lives on the `bun-legacy` branch.**

## Disclaimer — personal use only

This project exists for **personal automation on your own infrastructure, against your own Claude.ai subscription, called only by you.** That is the only use I (the author) endorse or support.

I do **not** accept, sanction, or assist any of the following:

- Commercialization — wrapping this in a product, reselling access, or offering it as a service to other users.
- Subscription pooling, account sharing, or any "relay-as-a-service" pattern that fans subscription access out to third parties.
- Bounties, payments, sponsorships, or any other incentive offered in exchange for sharing, leaking, or otherwise distributing Claude.ai account credentials, OAuth tokens, or session state. I will refuse such offers and report attempts to coordinate them.
- Use that violates [Anthropic's Usage Policy](https://www.anthropic.com/legal/aup) or the [Claude.ai Consumer Terms](https://www.anthropic.com/legal/consumer-terms).

Using this code is at your own risk. Anthropic actively enforces against subscription-relay abuse — throttling, suspension, and termination are all on the table. You are solely responsible for staying within the ToS that govern your own account.

## Stack

- Elixir 1.19, OTP 29
- Phoenix 1.8 (no HTML, no assets, no Ecto) on Bandit
- `Task.Supervisor` per request, isolating each `claude -p` subprocess

## Setup

Requires Elixir/OTP and the `claude` CLI installed and authenticated against your Claude.ai subscription.

```sh
mix deps.get
cp .env.example .env  # edit GATEWAY_TOKEN
mix phx.server
```

Smoke test:

```sh
curl -s http://localhost:4000/health

curl -s http://localhost:4000/v1/messages \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"say hi in five words"}]}'
```

## VPS deploy

1. Install Erlang/OTP and Elixir on the VPS (e.g. via `asdf` or distro packages).
2. Install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`.
3. Authenticate locally (`claude` → `/login` → pick your Claude.ai subscription account).
4. Copy auth state from laptop to VPS:
   ```sh
   scp ~/.claude/.credentials.json vps:~/.claude/.credentials.json
   scp ~/.claude.json vps:~/.claude.json
   ```
5. On the VPS, verify with `claude -p "hello"` before starting the gateway.
6. Build a release: `MIX_ENV=prod mix release`. Run under systemd, behind Caddy/Nginx for TLS.

Required prod env: `GATEWAY_TOKEN`, `SECRET_KEY_BASE`, `PHX_HOST`, `PHX_SERVER=true`.

## Endpoints

- `GET /health` — unauthenticated liveness probe.
- `POST /v1/messages` — Anthropic-shaped request, returns Anthropic-shaped response. Bearer auth required.

## Architecture notes

- `ClaudePGateway.Claude.run/2` spawns each `claude -p` invocation inside a supervised `Task` with a 5-minute timeout. Crashes, hangs, and non-zero exits are caught and surfaced as structured JSON errors rather than 500s.
- The gateway token is read at runtime via `config/runtime.exs` from `GATEWAY_TOKEN`; auth is constant-time via `Plug.Crypto.secure_compare/2`.
- No streaming yet. Planned: add `--output-format stream-json` and SSE via `Plug.Conn.chunk/2`.

## License

Released under the [PolyForm Noncommercial License 1.0.0](./LICENSE). Personal and noncommercial use is permitted; commercial use is not. No warranty of any kind is provided.
