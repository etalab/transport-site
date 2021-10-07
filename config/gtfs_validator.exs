use Mix.Config

# Configure GTFS Validator
config :transport,
   # by default, use the production validator. This can be overriden with dev.secret.exs
   gtfs_validator_url: System.get_env("GTFS_VALIDATOR_URL", "https://transport-validator.cleverapps.io")

config :validation,
  mobility_data: [
    bin: System.get_env("VALIDATOR_MOBILITY_DATA_BIN"),
    working_directory: System.get_env("VALIDATOR_MOBILITY_DATA_BIN", "./validations/gtfs/mobility_data/outputs")
  ]
