use Mix.Config

# Configure GTFS Validator
config :transport, gtfs_validator_url: System.get_env("GTFS_VALIDATOR_URL")
