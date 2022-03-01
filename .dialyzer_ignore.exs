[
  # temporary fix for https://github.com/elixir-ecto/postgrex/issues/549
  ~r/deps\/postgrex\/lib\/postgrex\/type_module.ex/,
  ~r/lib\/postgrex\/type_module.ex/,
  # EctoInterval raises an unknown_type error
  ~r/lib\/db\/gtfs_stop_times.ex/
]
