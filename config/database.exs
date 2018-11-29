use Mix.Config

config :transport, Transport.Repo,
  url: System.get_env("PG_URL") || "ecto://postgres:postgres@localhost/transport_repo",
  pool_size: (System.get_env("PG_POOL_SIZE") || "10") |> String.to_integer,
  types: Transport.PostgresTypes

config :transport, ecto_repos: [Transport.Repo]

config :ecto_sql, postgres_map_type: "json"

config :transport, Transport.Repo, types: Transport.PostgrexTypes
