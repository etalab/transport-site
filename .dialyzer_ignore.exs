[
  # temporary fix for https://github.com/elixir-ecto/postgrex/issues/549
  ~r/deps\/postgrex\/lib\/postgrex\/type_module.ex/,
  ~r/lib\/postgrex\/type_module.ex/,
  # EctoInterval raises an unknown_type error
  ~r/gtfs_stop_times.ex/,
  # Cloak.Ecto.SHA256 and DB.Encrypted.Binary raise an unknown_type error
  # See https://github.com/danielberkompas/cloak_ecto/issues/55
  {"lib/db/contact.ex", :unknown_type, 0},
  {"lib/db/user_feedback.ex", :unknown_type, 0},
  {"lib/db/notification.ex", :unknown_type, 0},
  ~r/lib\/cldr.ex/
]
