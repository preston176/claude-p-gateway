# claude-p-gateway

Minimal Anthropic-compatible HTTP gateway that proxies requests to a locally-authenticated `claude -p`. Lets other tools call your Claude Code CLI (authenticated with a Claude.ai subscription) over the network without consuming API credits.

## Disclaimer — personal use only

This project exists for **personal automation on your own infrastructure, against your own Claude.ai subscription, called only by you.** That is the only use I (the author) endorse or support.

I do **not** accept, sanction, or assist any of the following:

- Commercialization — wrapping this in a product, reselling access, or offering it as a service to other users.
- Subscription pooling, account sharing, or any "relay-as-a-service" pattern that fans subscription access out to third parties.
- Bounties, payments, sponsorships, or any other incentive offered in exchange for sharing, leaking, or otherwise distributing Claude.ai account credentials, OAuth tokens, or session state. I will refuse such offers and report attempts to coordinate them.
- Use that violates [Anthropic's Usage Policy](https://www.anthropic.com/legal/aup) or the [Claude.ai Consumer Terms](https://www.anthropic.com/legal/consumer-terms).

Using this code is at your own risk. Anthropic actively enforces against subscription-relay abuse — throttling, suspension, and termination are all on the table. You are solely responsible for staying within the ToS that govern your own account.

## License

Released under the [PolyForm Noncommercial License 1.0.0](./LICENSE). Personal and noncommercial use is permitted; commercial use is not. No warranty of any kind is provided.

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
- See the [Disclaimer](#disclaimer--personal-use-only) above — personal use only, no commercialization, no credential sharing.
- No streaming yet. Add `--output-format stream-json` and SSE when needed.
