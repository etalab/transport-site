use Mix.Config

# MongoDB configuration.
config :mongodb, url: System.get_env("MONGODB_URL")
