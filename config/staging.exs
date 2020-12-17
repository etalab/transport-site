use Mix.Config
alias Datagouvfr.Authentication

config :transport, TransportWeb.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [scheme: "https", host: "http://prochainement-transport.cleverapps.io", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :logger, level: :warn

config :transport, show_runtime_version: true

config :oauth2, Authentication,
  site: "https://demo.data.gouv.fr"
