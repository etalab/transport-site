import Config

config :transport,
  # The key used by Cloak. See `Transport.Vault`.
  # This value should be base64 encrypted
  # See https://github.com/danielberkompas/cloak#configuration
  cloak_key: System.get_env("CLOAK_KEY"),
  s3_buckets: %{
    history: "resource-history-prod",
    on_demand_validation: "on-demand-validation-prod",
    gtfs_diff: "gtfs-diff-prod",
    logos: "logos-prod",
    aggregates: "aggregates-prod"
  }

# Configure Sentry for production and staging.
# Check out https://sentry.io/settings/transport-data-gouv-fr/projects/transport-site/install/elixir/
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  csp_url: System.get_env("SENTRY_CSP_URL")

# `phoenix_ddos` is called in our own Plug `TransportWeb.Plugs.RateLimiter`
config :phoenix_ddos,
  safelist_ips: "PHOENIX_DDOS_SAFELIST_IPS" |> System.get_env("") |> String.split("|") |> Enum.reject(&(&1 == "")),
  blocklist_ips: "PHOENIX_DDOS_BLOCKLIST_IPS" |> System.get_env("") |> String.split("|") |> Enum.reject(&(&1 == "")),
  protections: [
    # ip rate limit
    {PhoenixDDoS.IpRateLimit,
     allowed: "PHOENIX_DDOS_MAX_2MIN_REQUESTS" |> System.get_env("500") |> Integer.parse() |> elem(0),
     period: {2, :minutes}},
    {PhoenixDDoS.IpRateLimit,
     allowed: "PHOENIX_DDOS_MAX_1HOUR_REQUESTS" |> System.get_env("10000") |> Integer.parse() |> elem(0),
     period: {1, :hour}},
    # ip rate limit on specific request_path
    {PhoenixDDoS.IpRateLimitPerRequestPath, request_paths: [{:get, "/login"}], allowed: 5, period: {30, :seconds}},
    {PhoenixDDoS.IpRateLimitPerRequestPath, request_paths: [{:post, "/send_mail"}], allowed: 1, period: {30, :seconds}}
  ]

# Do not print debug messages in production
config :logger, level: :info
