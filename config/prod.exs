use Mix.Config

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [scheme: "https", host: System.get_env("DOMAIN_NAME") || "transport.data.gouv.fr", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :gbfs, GBFSWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :transport, Transport.Scheduler,
  jobs: [
    {"0 7 * * *", {Transport.ImportData, :import_validate_all, []}}, # Every day at 7am
    {"@daily", {Transport.DataChecker, :outdated_data, []}}, # Send email for outdated data
    {"@daily", {Transport.DataChecker, :inactive_data, []}}, # Set inactive data
    {"@daily", {Transport.History, :backup_resources, []}}, # backup all resources
    {"@daily", {Transport.Gtfs2Netexfr, :convert_all, []}} # genrate a NeTEx file for all GTFS
  ]

config :db, DB.Repo,
  url: System.get_env("POSTGRESQL_ADDON_URI") || "" |> String.replace_prefix("postgresql", "ecto"),
  pool_size: 2,
  pool_timeout: 15_000,
  timeout: 15_000

# Do not print debug messages in production
config :logger, level: :info
