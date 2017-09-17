use Mix.Config

alias Transport.Datagouvfr.Authentication

# Configure data.gouv.fr
config :oauth2, Authentication,
  strategy: Authentication,
  site: System.get_env("DATAGOUVFR_SITE"),
  client_id: System.get_env("DATAGOUVFR_CLIENT_ID"),
  client_secret: System.get_env("DATAGOUVFR_CLIENT_SECRET"),
  redirect_uri: System.get_env("DATAGOUVFR_REDIRECT_URI")
