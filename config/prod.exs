use Mix.Config

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [scheme: "https", host: System.get_env("DOMAIN_NAME") || "transport.data.gouv.fr", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :gbfs, GBFSWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")

config :transport, Transport.Scheduler,
  jobs: [
    # Every day at 4am UTC
    {"0 4 * * *", {Transport.ImportData, :import_validate_all, []}},
    # Send email for outdated data
    {"@daily", {Transport.DataChecker, :outdated_data, []}},
    # Set inactive data
    {"@daily", {Transport.DataChecker, :inactive_data, []}},
    # backup all resources
    {"@daily", {Transport.History, :backup_resources, []}},
    # clean old logs
    {"0 3 * * *", {Transport.LogCleaner, :clean_old_logs, []}},
    # clean old validations
    {"0 2 * * *", {Transport.ValidationCleaner, :clean_old_validations, []}},
    # compute some global stats and store them in the DB
    {"0 20 * * *", {Transport.StatsHandler, :store_stats, []}},
    # generate NeTEx / geojson files for all GTFS.
    # Note : this should be run before the import_validate_all for the NeTEx / geojson
    # to be created when the import is run
    {"0 1 * * *", {Transport.GtfsConversions, :convert_all, []}},
    {"0 * * * *", {Transport.ImportData, :refresh_places, []}}
  ]

config :db, DB.Repo,
  url:
    System.get_env("POSTGRESQL_ADDON_DIRECT_URI") || System.get_env("POSTGRESQL_ADDON_URI") ||
      "" |> String.replace_prefix("postgresql", "ecto"),
  pool_size: (System.get_env("PG_POOL_SIZE") || "10") |> String.to_integer,
  pool_timeout: 15_000,
  timeout: 15_000

# Do not print debug messages in production
config :logger, level: :info
