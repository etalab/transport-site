use Mix.Config

config :gbfs, GBFSWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "npd4It199m0VTPg1DHnKP3yx6rjHB7jXqbD93lwdIgJJLvUvQfexm1xFTyaPp4L9",
  render_errors: [view: GBFSWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: GBFS.PubSub, adapter: Phoenix.PubSub.PG2],
  server: false

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{Mix.env()}.exs"
