defmodule Transport.Jobs.BNLCToGeoData do
  @moduledoc """
  Job in charge of taking the content of the BNLC (Base Nationale de Covoiturage) and storing it
  in the geo_data table
  """
  use Oban.Worker, max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(%{}) do
    Transport.ConsolidatedDataset.resource(:bnlc)
    |> Transport.Jobs.BaseGeoData.import_replace_data(&prepare_data_for_insert/2)

    :ok
  end

  def prepare_data_for_insert(body, geo_data_import_id) do
    prepare_data_fn = fn m ->
      %{
        geo_data_import_id: geo_data_import_id,
        geom: %Geo.Point{
          coordinates:
            {m["Xlong"] |> Transport.Jobs.BaseGeoData.parse_coordinate(),
             m["Ylat"] |> Transport.Jobs.BaseGeoData.parse_coordinate()},
          srid: 4326
        },
        payload: m |> Map.drop(["Xlong", "Ylat"])
      }
    end

    Transport.Jobs.BaseGeoData.prepare_csv_data_for_import(body, prepare_data_fn)
  end
end
