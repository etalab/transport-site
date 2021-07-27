use Mix.Config

# Configure GTFS Validator
config :transport,
       # by default, use the production validator. This can be overriden with dev.secret.exs
       gtfs_validator_url: "https://transport-validator.cleverapps.io"
#       gtfs_validator_url: System.get_env("GTFS_VALIDATOR_URL")
