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
    on_demand_validation: "on-demand-validation-prod"
  }

config :gbfs, GBFSWeb.Endpoint, secret_key_base: System.get_env("SECRET_KEY_BASE")

# Do not print debug messages in production
config :logger, level: :info
