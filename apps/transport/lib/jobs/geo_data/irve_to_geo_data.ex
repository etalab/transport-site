defmodule Transport.Jobs.IRVEToGeoData do
  @moduledoc """
  Job in charge of taking the charge stations stored in the Base nationale des Infrastructures de Recharge pour Véhicules Électriques and storing the result in the `geo_data` table.
  """
  alias NimbleCSV.RFC4180, as: CSV


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
end
