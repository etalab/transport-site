use Mix.Config

alias Datagouvfr.Authentication

# Configure data.gouv.fr
config :transport, datagouvfr_site: System.get_env("DATAGOUVFR_SITE")
config :transport, datagouvfr_apikey: System.get_env("DATAGOUVFR_APIKEY")

# Configure data.gouv.fr authentication
config :oauth2, Authentication,
  strategy: Authentication,
  site: System.get_env("DATAGOUVFR_SITE"),
  client_id: System.get_env("DATAGOUVFR_CLIENT_ID"),
  client_secret: System.get_env("DATAGOUVFR_CLIENT_SECRET"),
  redirect_uri: System.get_env("DATAGOUVFR_REDIRECT_URI")

config :oauth2,
  serializers: %{
    "multipart/form-data" => Transport.Datagouvfr.MultipartSerializer,
    "application/json"    => Poison
  }
