# explore the data gouv API to find a set of valid & invalid files

my_app_root = Path.join(__DIR__, "../..")

# hybrid setup to rely on the whole app setup but increment with a specificy dependency
Mix.install(
  [
    {:my_app, path: my_app_root, env: :dev},
    {:io_ansi_table, "~> 1.0"}
  ],
  config_path: Path.join(my_app_root, "config/config.exs"),
  lockfile: Path.join(my_app_root, "mix.lock")
)

resources =
  Transport.IRVE.Extractor.datagouv_resources()
  |> Transport.IRVE.RawStaticConsolidation.exclude_irrelevant_resources()

resources
|> Enum.map(& &1.valid)
|> Enum.frequencies()
|> IO.inspect(IEx.inspect_opts())

[{false, 10}, {true, 5}, {nil, 3}]
|> Enum.each(fn {validity, count} ->
  IO.puts("========= Validity: #{validity |> inspect} =========")
  rows = resources |> Enum.filter(&(&1.valid == validity)) |> Enum.take(count)

  IO.ANSI.Table.start([:dataset_organisation_id, :dataset_organisation_url, :valid, :validation_date, :last_modified],
    sort_specs: [desc: :rows],
    max_width: :infinity
  )

  IO.ANSI.Table.format(rows)
  IO.ANSI.Table.stop()
end)
