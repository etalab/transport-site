defmodule Transport.Registry.Engine do
  @moduledoc """
  Stream eligible resources and run extractors to produce a raw registry at the end.
  """

  alias Transport.Registry.GTFS
  alias Transport.Registry.Model.DataSource
  alias Transport.Registry.Model.Stop
  alias Transport.Registry.NeTEx
  alias Transport.Registry.Result

  import Ecto.Query

  require Logger

  @type option :: {:limit, integer()} | {:formats, [String.t()]}

  @doc """
  execute("/tmp/registre-arrets.csv", formats: ~w(GTFS NeTEx), limit: 100)
  """
  @spec execute(output_file :: Path.t(), opts :: [option]) :: :ok
  def execute(output_file, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1_000_000)
    formats = Keyword.get(opts, :formats, ~w(GTFS NeTEx))

    create_empty_csv_with_headers(output_file)

    enumerate_resources(limit, formats)
    |> Result.map_result(&prepare_extractor/1)
    |> Task.async_stream(&download/1, max_concurrency: 12, timeout: 30 * 60_000)
    # one for Task.async_stream
    |> Result.cat_results()
    # one for download/1
    |> Result.cat_results()
    |> Result.map_result(&extract_from_archive/1)
    |> dump_to_csv(output_file)
  end

  def create_empty_csv_with_headers(output_file) do
    headers = NimbleCSV.RFC4180.dump_to_iodata([Stop.csv_headers()])
    File.write(output_file, headers)
  end

  def enumerate_resources(limit, formats) do
    DB.Resource.base_query()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> where([resource: r], r.format in ^formats)
    |> preload([resource_history: rh], resource_history: rh)
    |> limit(^limit)
    |> DB.Repo.all()
  end

  def prepare_extractor(%DB.Resource{} = resource) do
    data_source_id = "datagouv:resource:#{resource.datagouv_id}"

    case resource.format do
      "GTFS" -> {:ok, {GTFS, data_source_id, resource.url}}
      "NeTEx" -> {:ok, {NeTEx, data_source_id, resource.url}}
      _ -> {:error, "Unsupported format"}
    end
  end

  def download({extractor, data_source_id, url}) do
    Logger.debug("download #{extractor} #{data_source_id} #{url}")
    tmp_path = System.tmp_dir!() |> Path.join("#{Ecto.UUID.generate()}.dat")

    safe_error = fn msg ->
      File.rm(tmp_path)
      Result.error(msg)
    end

    http_result =
      Transport.HTTPClient.get(url,
        decode_body: false,
        compressed: false,
        into: File.stream!(tmp_path)
      )

    case http_result do
      {:error, error} ->
        safe_error.("Unexpected error while downloading the resource from #{url}: #{Exception.message(error)}")

      {:ok, %{status: status}} ->
        cond do
          status >= 200 && status < 300 ->
            {:ok, {extractor, data_source_id, tmp_path}}

          status > 400 ->
            safe_error.("Error #{status} while downloading the resource from #{url}")

          true ->
            safe_error.("Unexpected HTTP error #{status} while downloading the resource from #{url}")
        end
    end
  end

  @spec extract_from_archive({module(), DataSource.data_source_id(), Path.t()}) :: Result.t([Stop.t()])
  def extract_from_archive({extractor, data_source_id, file}) do
    Logger.debug("extract_from_archive #{extractor} #{data_source_id} #{file}")
    extractor.extract_from_archive(data_source_id, file)
  end

  def dump_to_csv(enumerable, output_file) do
    enumerable
    |> Stream.concat()
    |> Stream.map(&Stop.to_csv/1)
    |> NimbleCSV.RFC4180.dump_to_stream()
    |> Stream.into(File.stream!(output_file, [:append, :utf8]))
    |> Stream.run()
  end
end
