use Mix.Config

config :db, DB.Repo,
  url: System.get_env("PG_URL") || "ecto://postgres:postgres@localhost/transport_repo",
  pool_size: (System.get_env("PG_POOL_SIZE") || "10") |> String.to_integer,
  types: DB.PostgrexTypes

config :db, ecto_repos: [DB.Repo]
config :transport, ecto_repos: [DB.Repo]

config :ecto_sql, postgres_map_type: "json"