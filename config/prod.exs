use Mix.Config

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}, compress: true],
  url: [scheme: "https", host: System.get_env("DOMAIN_NAME") || "transport.data.gouv.fr", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  live_view: [
    signing_salt: System.get_env("SECRET_KEY_BASE")
  ]

config :gbfs, GBFSWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")

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
