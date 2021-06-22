use Mix.Config

# One can use this as a template to create their own optional dev.secret.exs (not stored in git)
# with credentials sourced from the rest of the team.

# Careful about https://github.com/etalab/transport_deploy/issues/36, make sure
# to avoid using credentials with production access here:
config :transport, datagouvfr_apikey: "TO-BE-REPLACED"
config :oauth2, Datagouvfr.Authentication,
  client_id: "TO-BE-REPLACED",
  client_secret: "TO-BE-REPLACED",

# NOTE: we will replace this by a proxy config (https://github.com/etalab/transport-proxy-config) ultimarely
config :gbfs, jcdecaux_apikey: "TO-BE-REPLACED"

# use mix phx.gen.secret to generate a custom value for this
secret_key_base = "TO-BE-REPLACED"

config :transport, TransportWeb.Endpoint,
  secret_key_base: secret_key_base,
  live_view: [
    # NOTE: unsure if this is actually great to reuse the same value
    signing_salt: secret_key_base
  ]
