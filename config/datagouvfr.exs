import Config

alias Datagouvfr.Authentication

# Configure data.gouv.fr
config :transport, datagouvfr_site: System.get_env("DATAGOUVFR_SITE")
config :transport, datagouvfr_apikey: System.get_env("DATAGOUVFR_API_KEY")

config :transport,
  datagouvfr_transport_publisher_label: "Point d'Accès National transport.data.gouv.fr",
  datagouvfr_transport_publisher_id: "5abca8d588ee386ee6ece479",
  datagouvfr_publisher_id: "646b7187b50b2a93b1ae3d45",
  # https://www.data.gouv.fr/fr/organizations/autorite-de-regulation-des-transports-anciennement-arafer/
  datagouvfr_art_organization_id: "5a65deb788ee38279c49d926"

# Configure data.gouv.fr authentication

# transport acts as a client application of data.gouv.fr. When a user logs in on transport using its
# data.gouv.fr credentials, it gives the possibility to the transport website to request a token to data.gouv.fr
# allowing the user to e.g. post a comment on data.gouv.fr from the transport website.
# Our application (transport) has a client_id and a client_secret used to authenticate our application
# on data.gouv.fr's authorization server. There is no GUI to request or refresh those 2 informations : they have
# been personnaly given to us by the data.gouv.fr team.

config :oauth2, Authentication,
  strategy: Authentication,
  site: System.get_env("DATAGOUVFR_SITE"),
  client_id: System.get_env("DATAGOUVFR_CLIENT_ID"),
  client_secret: System.get_env("DATAGOUVFR_CLIENT_SECRET"),
  redirect_uri: URI.to_string(%URI{scheme: "https", host: System.get_env("DOMAIN_NAME"), path: "/login/callback"})

config :oauth2,
  adapter: Tesla.Adapter.Hackney
