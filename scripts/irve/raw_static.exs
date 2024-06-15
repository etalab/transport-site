#! /usr/bin/env mix run

# Start adding up everything we have, pre-consolidation, unfiltered, so that
# we can have solid discussions about the content, the validation of each file,
# the ids, and who should win when duplicates arise.

require Logger

Application.put_env(:transport, :irve_consolidation_caching, true)

schema_file = "cache-dir/schema-irve-statique.json"

unless File.exists?(schema_file) do
  %{status: 200} =
    Transport.HTTPClient.get!(
      "https://schema.data.gouv.fr/schemas/etalab/schema-irve-statique/latest/schema-statique.json",
      into: File.stream!(schema_file)
    )
end

Transport.IRVE.Extractor.resources()
|> Stream.map(fn r ->
  data_file = Path.join("cache-dir", r.resource_id <> ".dat")
  status_file = data_file <> ".status.json"

  unless File.exists?(data_file) do
    Logger.info("Processing #{data_file}...")
    %{status: status} = Transport.HTTPClient.get!(r.url, decode_body: false, into: File.stream!(data_file))
    File.write!(status_file, %{status: status} |> Jason.encode!())
  end

  r
  |> Map.put(:data_file_name, data_file)
  |> Map.put(:status, File.read!(status_file) |> Jason.decode!() |> Map.fetch!("status"))
end)
# |> Stream.take(1)
|> Stream.each(fn
  %{status: 200} = x ->
    IO.inspect(x, IEx.inspect_opts())
    IO.inspect(Transport.IRVE.FrictionlessCLIValidator.validate(x.data_file_name, schema_file), IEx.inspect_opts())
end)
|> Stream.run()
