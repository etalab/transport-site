import Config

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}, compress: true],
  url: [scheme: "https", host: System.get_env("DOMAIN_NAME", "transport.data.gouv.fr"), port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  live_view: [
    signing_salt: System.get_env("SECRET_KEY_BASE")
  ]

config :transport,
  s3_buckets: %{
    history: "resource-history-prod",
    on_demand_validation: "on-demand-validation-prod",
    gtfs_diff: "gtfs-diff-prod"
  }

# Configure Sentry for production and staging.
# Check out https://sentry.io/settings/transport-data-gouv-fr/projects/transport-site/install/elixir/
config :sentry,
  # Sentry events are only sent when `dsn` is not nil
  # https://hexdocs.pm/sentry/upgrade-10-x.html#stop-using-included_environments
  dsn: System.get_env("SENTRY_DSN"),
  csp_url: System.get_env("SENTRY_CSP_URL"),
  environment_name: "SENTRY_ENV" |> System.get_env(to_string(config_env())) |> String.to_atom(),
  enable_source_code_context: true,
  # https://hexdocs.pm/sentry/Sentry.html#module-configuration
  # > a list of paths to the root of your application's source code.
  # > For umbrella apps, you should set this to all the application paths in your umbrella
  # Caveat: https://github.com/getsentry/sentry-elixir/issues/638
  root_source_code_paths: [File.cwd!() |> Path.join("apps")],
  filter: Transport.Shared.SentryExceptionFilter

config :gbfs, GBFSWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")

# Do not print debug messages in production
config :logger, level: :info
