import Config

config :transport, DB.Repo,
  url: System.get_env("PG_URL") || "ecto://postgres:postgres@localhost/transport_repo",
  # NOTE: this default pool_size is overriden by "prod.exs" !
  pool_size: 50,
  types: DB.PostgrexTypes,
  log: false

config :transport, ecto_repos: [DB.Repo]
config :transport, ecto_repos: [DB.Repo]
