# claude-p-gateway

A small HTTP server in front of the `claude` CLI. Send it a request shaped like Anthropic's `/v1/messages`, it shells out to `claude -p`, and hands the response back. The point is to route work through a Claude.ai subscription you already pay for, instead of buying API credits on top.

Phoenix on Bandit, API only, no Ecto. Each call to `claude -p` runs inside a supervised task so a stuck or crashing CLI invocation cannot take the gateway down with it. Streaming responses are translated into Anthropic's `/v1/messages` event vocabulary, and a global token-bucket sits in front of the CLI so concurrent calls cannot burn through a subscription window unchecked.

> The earlier Bun and Hono version of this is still around on the `bun-legacy` branch if you want to compare.

## Disclaimer (please read)

This is built for personal automation. Your own VPS, your own subscription, your own scripts hitting the endpoint. That is the use case I built it for, and the only one I will support.

A few things I will not help with:

- Wrapping this in a product, selling access, or running it as a service for other people.
- Pooling subscriptions, sharing accounts, or fanning one Claude.ai login out across multiple users. That is a "relay as a service" and I am not interested.
- Any kind of bounty, payment, or sponsorship in exchange for sharing credentials, OAuth tokens, or session state from a Claude.ai account. Do not ask. If anyone tries to coordinate one, I will report it.
- Anything that crosses the lines in [Anthropic's Usage Policy](https://www.anthropic.com/legal/aup) or the [Claude.ai Consumer Terms](https://www.anthropic.com/legal/consumer-terms).

Use this at your own risk. Anthropic does enforce against people using subscriptions as relays, and throttling, suspension, and termination are all on the table. Staying inside the terms that govern your account is your responsibility, not mine.

## Stack

Elixir 1.19 on OTP 29. Phoenix 1.8 (no HTML templates, no assets pipeline, no mailer, no Ecto) running on Bandit. Most of the actual work happens inside the `claude` binary; the gateway is a thin routing and supervision layer around `System.cmd` and `Port`.

## Local setup

You need Elixir, OTP, and the `claude` CLI installed. The CLI has to be authenticated against your Claude.ai subscription before any of this is useful. Run `claude` interactively once, hit `/login`, and pick your account.

```sh
mix deps.get
cp .env.example .env
# edit .env, set a long random GATEWAY_TOKEN
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

Tests:

```sh
mix test
```

## Deploying to a VPS

The full walkthrough lives in [`deploy/README.md`](./deploy/README.md). It covers the service user, copying `claude` credentials across, building the release, the systemd unit, Caddy with automatic TLS, and the admin pages.

Short version:

1. Authenticate `claude` on your laptop, then copy `~/.claude/.credentials.json` and `~/.claude.json` into the service user's home on the VPS.
2. Build a release with `MIX_ENV=prod mix release`, then rsync it to `/opt/claude-p-gateway`.
3. Drop `deploy/systemd/claude-p-gateway.service` into `/etc/systemd/system/`, fill out `/etc/claude-p-gateway/env`, then `systemctl enable --now claude-p-gateway`.
4. Use [`deploy/caddy/Caddyfile.example`](./deploy/caddy/Caddyfile.example) as a starting point for TLS.

Required production env vars: `GATEWAY_TOKEN`, `SECRET_KEY_BASE`, `PHX_HOST`, `PHX_SERVER=true`. Strongly recommended: `STATE_PATH` so settings edited via the admin page survive restarts. Set `DASHBOARD_USER` and `DASHBOARD_PASS` if you want the admin pages exposed.

## Endpoints

`GET /health` is an unauthenticated liveness probe. Returns `{"ok": true}`.

`POST /v1/messages` takes an Anthropic-shaped request and returns an Anthropic-shaped response. Bearer auth required. Set `"stream": true` in the body to switch to server-sent events; frames come back in Anthropic's streaming vocabulary (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`). Returns `429` with a `Retry-After` header and a `retry_after_ms` field when the rate limiter is empty.

`GET /admin/settings` is a small HTML form for rotating the gateway token and tuning the rate limit at runtime. Protected by the same BasicAuth credentials as the dashboard.

`GET /admin/dashboard` is the Phoenix LiveDashboard. Both admin routes return `404` unless both `DASHBOARD_USER` and `DASHBOARD_PASS` are set, so unauthenticated probers cannot even discover they exist.

## Runtime configuration

The gateway token, rate limit capacity, and rate limit refill rate are held in a `Settings` GenServer that is seeded from environment variables on boot. The admin settings page can mutate any of them at runtime. If `STATE_PATH` is set, changes are persisted to that JSON file and survive restarts; otherwise they live in memory only.

Rate limiting is a single global token bucket. The defaults are 60 tokens with a refill of 60 per minute, which is generous for a one-person personal workload. Tune to taste from `/admin/settings`.

## How it works

`ClaudePGateway.Claude.run/2` runs each `claude -p` call inside a supervised task with a five-minute timeout. Crashes, hangs, and non-zero exits get caught and turned into structured JSON errors instead of bare 500s.

Streaming opens a `Port` against `claude -p --output-format stream-json --verbose` and reads line by line. Each NDJSON event is fed through `ClaudePGateway.AnthropicTranslator`, which converts claude's native event vocabulary (`system/init`, `assistant`, `result`) into the Anthropic streaming vocabulary clients expect. stderr is folded into stdout and any non-JSON lines are dropped, so spurious diagnostic output from the CLI does not poison the event stream.

Every request runs through `ClaudePGateway.RateLimiter.check/0` before the CLI is invoked. Failed checks short-circuit to a 429 with a `Retry-After` header derived from how many milliseconds the bucket needs to refill one token.

The gateway token check is constant-time via `Plug.Crypto.secure_compare/2`. The token itself is held in `Settings`, so rotating it from `/admin/settings` takes effect on the very next request without a restart.

Tests run against a Mox-generated implementation of `ClaudePGateway.ClaudeBehaviour`. The controller looks the implementation up out of application config, so the real `claude` binary is never invoked under test.

## License

Released under the [PolyForm Noncommercial License 1.0.0](./LICENSE). Personal and noncommercial use is allowed. Commercial use is not. No warranty.
