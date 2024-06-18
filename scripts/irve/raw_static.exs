#! /usr/bin/env mix run

# Start adding up everything we have, pre-consolidation, unfiltered, so that
# we can have solid discussions about the content, the validation of each file,
# the ids, and who should win when duplicates arise.

require Logger

Application.put_env(:transport, :irve_consolidation_caching, true)

schema_url = "https://schema.data.gouv.fr/schemas/etalab/schema-irve-statique/latest/schema-statique.json"
schema_file_path = "cache-dir/schema-irve-statique.json"

defmodule Script do
  # useful to cache schema path
  def download_if_needed!(url, file_path) do
    unless File.exists?(file_path) do
      %{status: 200} = Transport.HTTPClient.get!(url, into: File.stream!(file_path))
    end
  end

  def file_path_for_resource(resource_id), do: Path.join("cache-dir", resource_id <> ".dat")
  def status_file_path_for_resource(resource_id), do: file_path_for_resource(resource_id) <> ".status.json"

  # cache a resource file, including if it is non-200 (but timeout wasn't necessary to support here)
  # HTTP status is stored in a secondary JSON file
  def cached_resource_download(resource_id, url) do
    data_file = file_path_for_resource(resource_id)
    status_file = status_file_path_for_resource(resource_id)

    unless File.exists?(data_file) do
      Logger.info("Downloading #{data_file}...")
      %{status: status} = Transport.HTTPClient.get!(url, decode_body: false, into: File.stream!(data_file))
      File.write!(status_file, %{status: status} |> Jason.encode!())
    end

    %{
      data_file_path: data_file,
      http_status: status_file |> File.read!() |> Jason.decode!() |> Map.fetch!("status")
    }
  end
end

Script.download_if_needed!(schema_url, schema_file_path)

Transport.IRVE.Extractor.resources()
|> Task.async_stream(
  fn r ->
    r |> Map.merge(Script.cached_resource_download(r.resource_id, r.url))
  end,
  max_concurrency: 50
)
|> Stream.map(fn {:ok, r} -> r end)
# |> Stream.take(1)
|> Stream.each(fn
  %{http_status: 200} = x ->
    IO.inspect(x, IEx.inspect_opts())
    IO.inspect(Transport.IRVE.FrictionlessCLIValidator.validate(x.data_file_path, schema_file_path), IEx.inspect_opts())
end)
|> Stream.run()
