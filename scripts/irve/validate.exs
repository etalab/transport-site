test_resources = [
  # https://www.data.gouv.fr/datasets/infrastructures-de-recharge-pour-vehicules-electriques-donnees-ouvertes/
  %{url: "https://proxy.transport.data.gouv.fr/resource/qualicharge-irve-statique"},
  # https://www.data.gouv.fr/datasets/base-nationale-des-irve-infrastructures-de-recharge-pour-vehicules-electriques/
  %{url: "https://www.data.gouv.fr/api/1/datasets/r/eb76d20a-8501-400e-b336-d85724de5435"}
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

  Transport.LogTimeTaken.log_time_taken("Validating downloaded copy of #{url} (#{path})", fn ->
    df = Explorer.DataFrame.from_csv!(path, infer_schema_length: 0)

    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    # example of pre-processing to ensure Qualicharge resource follows the
    # exact requirement (`true` or `false`, no other strings)
    df =
      Explorer.DataFrame.mutate_with(df, fn df ->
        schema
        |> Map.fetch!("fields")
        |> Enum.filter(fn %{"type" => type} -> type == "boolean" end)
        |> Enum.map(fn %{"name" => name} ->
          {
            name,
            df[name]
            |> Explorer.Series.re_replace(~S/\ATrue\z/, "true")
            |> Explorer.Series.re_replace(~S/\AFalse\z/, "false")
          }
        end)
        |> Enum.into(%{})
      end)

    df =
      df
      |> Transport.IRVE.Validator.DataFrameValidation.setup_field_validation_columns(schema)
      |> Transport.IRVE.Validator.DataFrameValidation.setup_row_check()

    df["check_row_valid"]
    |> Explorer.Series.frequencies()
    |> IO.inspect(IEx.inspect_opts())
  end)
end)
