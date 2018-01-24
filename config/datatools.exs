use Mix.Config

# Configure datatools-server
config :transport, datatools_url: System.get_env("DATATOOLS_URL")
