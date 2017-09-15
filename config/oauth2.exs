use Mix.Config

alias Transport.OAuth2.Strategy.Datagouvfr

# Configure OAuth2's data.gouv.fr strategy
config :oauth2, Datagouvfr,
  strategy: Datagouvfr,
  site: System.get_env("DATAGOUVFR_SITE"),
  client_id: System.get_env("DATAGOUVFR_CLIENT_ID"),
  client_secret: System.get_env("DATAGOUVFR_CLIENT_SECRET"),
  redirect_uri: System.get_env("DATAGOUVFR_REDIRECT_URI")
