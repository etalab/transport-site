defmodule Transport.Jobs.IRVEToGeoData do
  @moduledoc """
  Job in charge of taking the charge stations stored in the Base nationale des Infrastructures de Recharge pour Véhicules Électriques and storing the result in the `geo_data` table.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  require Logger

  @datagouv_organization_id "646b7187b50b2a93b1ae3d45"
  @resource_datagouv_id "eb76d20a-8501-400e-b336-d85724de5435"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    [resource] =
      relevant_dataset()
      |> DB.Dataset.official_resources()
      |> Enum.filter(&match?(%DB.Resource{datagouv_id: @resource_datagouv_id, format: "csv"}, &1))

    Transport.Jobs.BaseGeoData.import_replace_data(resource, &prepare_data_for_insert/2)

    :ok
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

  def relevant_dataset do
    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == "charging-stations" and d.organization_id == @datagouv_organization_id)
    |> DB.Repo.one!()
  end
end
