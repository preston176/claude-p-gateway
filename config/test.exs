import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :claude_p_gateway, ClaudePGatewayWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "uR7EyS2DwOlI/5LzfYlGNvBtGtZH4l0JkWNm16WGvm/Mplq+2vo7lM+q1t+ZjsCw",
  server: false

config :claude_p_gateway, :claude_module, ClaudePGateway.MockClaude

# Effectively disable the rate limiter under test; tests that exercise
# rate limiting clamp it down explicitly via Settings.update/1.
config :claude_p_gateway, :settings_defaults, %{
  rate_limit_capacity: 1_000_000,
  rate_limit_refill_per_minute: 1_000_000
}

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
