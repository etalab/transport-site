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
    logos: "logos-prod"
  }

# Configure Sentry for production and staging.
# Check out https://sentry.io/settings/transport-data-gouv-fr/projects/transport-site/install/elixir/
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  csp_url: System.get_env("SENTRY_CSP_URL")

# Do not print debug messages in production
config :logger, level: :info
