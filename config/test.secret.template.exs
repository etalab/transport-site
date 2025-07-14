import Config

config :transport, DB.Repo,
  url: "ecto://transport_docker:coucou@localhost:6432/transport_test"
