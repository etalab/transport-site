defmodule Transport.Jobs.BNLCToGeoData do
  @moduledoc """
  Job in charge of taking the content of the BNLC (Base Nationale de Covoiturage) and storing it
  in the geo_data table
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias NimbleCSV.RFC4180, as: CSV
  require Logger

  @bnlc_dataset 253

  @impl Oban.Worker
  def perform(%{}) do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    # get the relevant dataset and its resource
    dataset =
      DB.Dataset
      |> preload(:resources)
      |> where([d], d.type == "carpooling-areas" and d.organization == ^transport_publisher_label)
      |> DB.Repo.one!()

    [%{id: resource_id}] = DB.Dataset.official_resources(dataset)

    %{id: latest_resource_history_id, payload: %{"permanent_url" => permanent_url}} =
      DB.ResourceHistory.latest_resource_history(resource_id)

    current_geo_data_import = DB.GeoDataImport.dataset_latest_geo_data_import(@bnlc_dataset)
    import_replace_data(permanent_url, latest_resource_history_id, current_geo_data_import)
    :ok
  end

  defp import_replace_data(_url, latest_resource_history_id, %{resource_history_id: latest_resource_history_id}) do
    Logger.info("nothing new to import for BNLC")
    :ok
  end

  defp import_replace_data(url, latest_resource_history_id, current_geo_data_import) do
    Logger.info("New BNLC content detected...update content")

    DB.Repo.transaction(fn ->
      unless is_nil(current_geo_data_import) do
        # thanks to cascading delete, it will also clean geo_data table corresponding entries
        current_geo_data_import |> DB.Repo.delete!()
      end

      %{id: geo_data_import_id} = DB.Repo.insert!(%DB.GeoDataImport{resource_history_id: latest_resource_history_id})

      http_client = Transport.Shared.Wrapper.HTTPoison.impl()
      %{status_code: 200, body: body} = http_client.get!(url)

      insert_bnlc_data(body, geo_data_import_id)
    end)

    :ok
  end

  def insert_bnlc_data(body, geo_data_import_id) do
    body
    |> prepare_data_for_insert(geo_data_import_id)
    |> Stream.chunk_every(1000)
    |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GeoData, chunk) end)
    |> Stream.run()
  end

  def prepare_data_for_insert(body, geo_data_import_id) do
    body
    |> CSV.parse_string(skip_headers: false)
    |> Stream.transform([], fn r, acc ->
      if acc == [] do
        {%{}, r}
      else
        {[acc |> Enum.zip(r) |> Enum.into(%{})], acc}
      end
    end)
    |> Stream.map(fn m ->
      %{
        geo_data_import_id: geo_data_import_id,
        geom: %Geo.Point{
          coordinates: {m["Xlong"] |> parse_coordinate(), m["Ylat"] |> parse_coordinate()},
          srid: 4326
        },
        payload: m |> Map.drop(["Xlong", "Ylat"])
      }
    end)
  end

  # remove spaces (U+0020) and non-break spaces (U+00A0) from the string
  defp string_to_float(s), do: s |> String.replace([" ", " "], "") |> String.to_float()

  # keep 6 digits for WGS 84, see https://en.wikipedia.org/wiki/Decimal_degrees#Precision
  defp parse_coordinate(s) do
    s |> string_to_float() |> Float.round(6)
  end
end
