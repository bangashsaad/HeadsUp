import Config

# Settlement: never let the worker auto-fire mid-test; tests drive it via
# Worker.trigger_now/0 or Settlement.settle_duel/1 with explicit past windows.
config :heads_up, :settlement_interval_ms, 3_600_000

# Same deal for the stale-duel janitor: tests call Contests.expire_stale/1.
config :heads_up, :janitor_interval_ms, 3_600_000
config :heads_up, :stats_provider, HeadsUp.Settlement.Stats.Mock

# No real pushes from tests; Notifications tests exercise deliver/4 directly
# with a Req.Test plug.
config :heads_up, HeadsUp.Notifications, enabled: false, req_options: []

# ESPN: point both host roots at an unroutable address so any un-stubbed
# real-feed call fails loudly instead of reaching the internet. Tests that
# exercise the client/provider inject a `Req.Test` plug + disable retry via
# `req_options` in their setup.
config :heads_up, HeadsUp.Sports.Espn,
  site_host: "http://localhost:0",
  web_host: "http://localhost:0",
  # retry: false so un-stubbed calls fail INSTANTLY (the draft server probes the
  # scoreboard on start; retry backoff would add seconds to every draft test).
  req_options: [retry: false]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :heads_up, HeadsUp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "heads_up_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :heads_up, HeadsUpWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Ztm3leaN1d48YOTYH4dpcm/3mUAUXDwA49Gydm10ifjrpM6wUsJSA/lRkDerrTzN",
  server: false

# In test we don't send emails
config :heads_up, HeadsUp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
