defmodule Transport.Jobs.BaseGeoData do
  @moduledoc """
  Shared methods for GeoData import jobs.
  """
  require Logger

  def insert_data(body, geo_data_import_id, prepare_data_for_insert_fn) do
    body
    |> prepare_data_for_insert_fn.(geo_data_import_id)
    |> Stream.chunk_every(1000)
    |> Stream.each(&DB.Repo.insert_all(DB.GeoData, &1))
    |> Stream.run()
  end

  def needs_import?(
        %DB.ResourceHistory{id: latest_resource_history_id},
        %DB.GeoDataImport{resource_history_id: resource_history_id}
      ),
      do: latest_resource_history_id != resource_history_id

  def needs_import?(_, nil), do: true

  def import_replace_data(%DB.Resource{id: resource_id, dataset_id: dataset_id}, prepare_data_for_insert_fn) do
    Logger.info("New content detected...update content")

    %{id: latest_resource_history_id, payload: %{"permanent_url" => permanent_url}} =
      latest_resource_history = DB.ResourceHistory.latest_resource_history(resource_id)

    current_geo_data_import = DB.GeoDataImport.dataset_latest_geo_data_import(dataset_id)

    needs_import = needs_import?(latest_resource_history, current_geo_data_import)

    DB.Repo.transaction(fn ->
      if needs_import and not is_nil(current_geo_data_import) do
        # thanks to cascading delete, it will also clean geo_data table corresponding entries
        current_geo_data_import |> DB.Repo.delete!()
      end

      if needs_import or is_nil(current_geo_data_import) do
        %{id: geo_data_import_id} = DB.Repo.insert!(%DB.GeoDataImport{resource_history_id: latest_resource_history_id})

        http_client = Transport.Shared.Wrapper.HTTPoison.impl()
        %{status_code: 200, body: body} = http_client.get!(permanent_url)

        insert_data(body, geo_data_import_id, prepare_data_for_insert_fn)
      end
    end)

    :ok
  end

  # keep 6 digits for WGS 84, see https://en.wikipedia.org/wiki/Decimal_degrees#Precision
  def parse_coordinate(s) do
    s |> string_to_float() |> Float.round(6)
  end

  # remove spaces (U+0020) and non-break spaces (U+00A0) from the string
  defp string_to_float(s), do: s |> String.replace([" ", " "], "") |> String.to_float()
end
