test_resources = [
  # https://www.data.gouv.fr/datasets/infrastructures-de-recharge-pour-vehicules-electriques-donnees-ouvertes/
  # %{url: "https://proxy.transport.data.gouv.fr/resource/qualicharge-irve-statique"},
  # https://www.data.gouv.fr/datasets/base-nationale-des-irve-infrastructures-de-recharge-pour-vehicules-electriques/
  # %{url: "https://www.data.gouv.fr/api/1/datasets/r/eb76d20a-8501-400e-b336-d85724de5435"},
  # https://www.data.gouv.fr/datasets/fichier-irve-gireve
  %{url: "https://www.data.gouv.fr/api/1/datasets/r/61387a4e-22f7-4662-b241-d5cac4dd91fd"},
  # Froth https://www.data.gouv.fr/datasets/bornes-de-recharges-reseau-froth
  %{url: "https://www.data.gouv.fr/api/1/datasets/r/20e9f13e-a3d4-470a-a356-5714b91cddce"}
]

cache_dir = Path.join(__DIR__, "../../cache-dir")
File.mkdir_p!(cache_dir)

test_resources
|> Enum.each(fn %{url: url} ->
  path = Path.join(cache_dir, "download-" <> Path.basename(url))

  if !File.exists?(path) do
    IO.puts("Downloading #{path}")
    Req.get!(url, into: File.stream!(path))
  else
    IO.puts("#{path} already there")
  end

  Transport.LogTimeTaken.log_time_taken("Validating #{path}", fn ->
    IO.puts("Starting validating downloaded copy of #{url} (#{path})…")
    df = Transport.IRVE.Validator.validate(path)

    IO.puts("Is the full file valid? #{df |> Transport.IRVE.Validator.full_file_valid?()}")

    IO.puts("Validation summary (how many rows are valid or invalid):")

    df["check_row_valid"]
    |> Explorer.Series.frequencies()
    |> IO.inspect(IEx.inspect_opts())

    report_columns = Transport.IRVE.StaticIRVESchema.field_names_list() |> Enum.map(&"check_column_#{&1}_valid")

    columns_with_false =
      report_columns
      |> Enum.reject(fn col ->
        df[col]
        |> Explorer.Series.all?()
      end)

    IO.puts("Columns with at least one invalid value: #{inspect(columns_with_false)}")

    report_path = Path.rootname(path) <> "-validation-report.csv"
    IO.puts("Writing validation report to #{report_path}")

    df |> Explorer.DataFrame.to_csv!(report_path)
  end)
end)
