defmodule Transport.Jobs.ParkingsRelaisToGeoData do
  @moduledoc """
  Job in charge of taking the parking relais stored in the Base nationale des parcs relais and storing the result in the `geo_data` table.
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%{}) do
    Transport.Jobs.BaseGeoData.import_replace_data(:parkings_relais, &prepare_data_for_insert/2)
  end

  defp pr_count(""), do: 0
  defp pr_count(str), do: String.to_integer(str)

  def prepare_data_for_insert(body, geo_data_import_id) do
    filter_fn = fn {:ok, line} -> pr_count(line["nb_pr"]) > 0 end

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

    Transport.Jobs.BaseGeoData.prepare_csv_data_for_import(body, prepare_data_fn,
      filter_fn: filter_fn,
      separator_char: ?;,
      escape_char: ?"
    )
  end
end
