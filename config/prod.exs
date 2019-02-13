use Mix.Config

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [scheme: "https", host: System.get_env("DOMAIN_NAME") || "transport.data.gouv.fr", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :transport, Transport.Scheduler,
  jobs: [
    {"0 7 * * *", {Transport.ImportData, :import_validate_all, []}}, # Every day at 7am
  ]

config :transport, Transport.Repo,
  url: System.get_env("POSTGRESQL_ADDON_URI") || "" |> String.replace_prefix("postgresql", "ecto"),
  pool_size: 2,
  pool_timeout: 15_000,
  timeout: 15_000

# Do not print debug messages in production
config :logger, level: :info

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: :prod,
  enable_source_code_context: true,
  root_source_code_path: File.cwd!,
  tags: %{
    env: "production"
  },
  included_environments: [:prod]
