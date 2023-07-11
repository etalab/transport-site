defmodule Transport.Jobs.IRVEToGeoData do
  @moduledoc """
  Job in charge of taking the charge stations stored in the Base nationale des Infrastructures de Recharge pour Véhicules Électriques and storing the result in the `geo_data` table.
  """

  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias NimbleCSV.RFC4180, as: CSV
  require Logger


  def perform(%{}) do # This could be shared with some options between files
    [resource] = relevant_dataset() |> DB.Dataset.official_resources() |> Enum.filter(&(&1.format == "csv"))

    Transport.Jobs.BaseGeoData.import_replace_data(resource, &prepare_data_for_insert/2)

    :ok
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
    |> Stream.map(fn m -> # Purquoi dans les parkings relais on met un :ok ?
      %{
        geo_data_import_id: geo_data_import_id,
        geom: %Geo.Point{
          coordinates:
            {m["consolidated_longitude"] |> Transport.Jobs.BaseGeoData.parse_coordinate(),
             m["consolidated_latitude"] |> Transport.Jobs.BaseGeoData.parse_coordinate()},
          srid: 4326
        },
        payload: m |> Map.drop(["consolidated_longitude", "consolidated_latitude", "coordonnesXY"])
      }
    end)
  end

  def relevant_dataset do
    # Etalab org ID is hardcoded, do not merge while it is the case
    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == "charging-stations" and d.organization_id == "534fff75a3a7292c64a77de4")
    |> DB.Repo.one!()
  end
end
