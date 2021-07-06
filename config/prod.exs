use Mix.Config

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [scheme: "https", host: System.get_env("DOMAIN_NAME") || "transport.data.gouv.fr", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  live_view: [
    signing_salt: System.get_env("SECRET_KEY_BASE")
  ]

config :gbfs, GBFSWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")

config :transport, Transport.Scheduler,
  jobs: [
    # Every day at 4am UTC
    {"0 4 * * *", {Transport.ImportData, :import_validate_all, []}},
    # Send email for outdated data
    {"@daily", {Transport.DataChecker, :outdated_data, []}},
    # Set inactive data
    {"@daily", {Transport.DataChecker, :inactive_data, []}},
    # Watch for new comments on datasets
    {"@daily", {Transport.CommentsChecker, :check_for_new_comments, []}},
    # Delete orphan community resources
    {"@daily", {Transport.CommunityResourcesCleaner, :clean_community_resources, []}},
    # backup all resources
    {"@daily", {Transport.History.Backup, :backup_resources, []}},
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
  pool_size: 10,
  # NOTE: pool_timeout is deprecated!
  # Must be replaced by https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config
  pool_timeout: 15_000,
  timeout: 15_000

# Do not print debug messages in production
config :logger, level: :info
