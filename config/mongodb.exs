use Mix.Config

config :mongodb, url: System.get_env("MONGODB_URL")
