use Mix.Config
alias Transport.Datagouvfr.Authentication

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :transport, TransportWeb.Endpoint,
  http: [port: 5001],
  server: true

# Integration testing with Hound and PhantomJS
config :hound, driver: "phantomjs"

# Print only warnings and errors during test
config :logger, level: :warn

# Configure data.gouv.fr authentication
config :oauth2, Authentication,
  site: "https://next.data.gouv.fr"

# MongoDB configuration.
config :mongodb, url: "mongodb://localhost/transport_test"

# Validator configuration
config :transport, gtfs_validator_url: System.get_env("GTFS_VALIDATOR_URL") || "http://127.0.0.1:7878"
