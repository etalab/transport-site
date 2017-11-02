use Mix.Config
alias Transport.Datagouvfr.Authentication

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [scheme: "https", host: "transport-site-staging.herokuapp.com", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :logger, level: :warn

config :oauth2, Authentication,
  site: "https://next.data.gouv.fr"
