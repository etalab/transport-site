defmodule Transport.Jobs.NeTExToGeoJSONConverterJob do
  @moduledoc """
  This will enqueue NeTEx -> GeoJSON conversion jobs for all NeTEx resources found in ResourceHistory.
  """
  use Oban.Worker, tags: ["conversions"], max_attempts: 3
  alias Transport.Jobs.NeTExGenericConverter

  @impl true
  def perform(%{}) do
    NeTExGenericConverter.enqueue_all_conversion_jobs("GeoJSON", Transport.Jobs.SingleNeTExToGeoJSONConverterJob)
  end
end

defmodule Transport.Jobs.SingleNeTExToGeoJSONConverterJob do
  @moduledoc """
  Conversion Job of a NeTEx to a GeoJSON, saving the resulting file in S3.
  """
  use Oban.Worker, tags: ["conversions"], max_attempts: 3
  alias Transport.Jobs.NeTExGenericConverter

  defdelegate converter(), to: Transport.NeTExToGeoJSONConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    NeTExGenericConverter.perform_single_conversion_job(
      resource_history_id,
      "GeoJSON",
      Transport.NeTExToGeoJSONConverter
    )
  end
end

defmodule Transport.NeTExToGeoJSONConverter do
  @moduledoc """
  Given a NeTEx file path, create from the file the corresponding geojson with the stops and line shapes if available.
  """
  @behaviour Transport.Converters.Converter

  def convert(netex_file_path, geojson_file_path) do
    with {:ok, json} <- Transport.NeTEx.ArchiveParser.to_geojson(netex_file_path),
         :ok <- File.write(geojson_file_path, JSON.encode!(json)) do
      :ok
    else
      {:error, e} when is_atom(e) -> {:error, to_string(e)}
      {:error, e} when is_binary(e) -> {:error, e}
    end
  end

  @impl true
  def converter, do: "etalab/transport-site"

  @impl true
  def converter_version, do: "0.1.0"
end
