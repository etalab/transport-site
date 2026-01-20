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
    df = Transport.IRVE.Validator.validate(path)

    df["check_row_valid"]
    |> Explorer.Series.frequencies()
    |> IO.inspect(IEx.inspect_opts())
  end)
end)
