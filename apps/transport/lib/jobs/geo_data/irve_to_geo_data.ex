defmodule Transport.Jobs.IRVEToGeoData do
  @moduledoc """
  Job in charge of taking the charge stations stored in the Base nationale des Infrastructures de Recharge pour Véhicules Électriques and storing the result in the `geo_data` table.
  """
  use Oban.Worker, max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Transport.Jobs.BaseGeoData.import_replace_data(:irve, &prepare_data_for_insert/2)
  end

  def prepare_data_for_insert(body, geo_data_import_id) do
    prepare_data_fn = fn m ->
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
    end

    Transport.Jobs.BaseGeoData.prepare_csv_data_for_import(body, prepare_data_fn)
  end
end
