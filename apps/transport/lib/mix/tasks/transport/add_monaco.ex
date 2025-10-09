defmodule Mix.Tasks.Transport.AddMonaco do
  @moduledoc """
  Adds Monaco as a country to the administrative_division table.
  Run with `mix Transport.AddMonaco`.
  """

  use Mix.Task
  require Logger

  @geojson_url "https://github.com/user-attachments/files/22597333/monaco.txt"

  def run(_params) do
    Logger.info("Adding Monaco to administrative_division table")

    Mix.Task.run("app.start")

    Logger.info("Downloading Monaco GeoJSON...")
    %{"features" => [%{"geometry" => geojson_data}]} = download_geojson()

    Logger.info("Inserting Monaco...")
    insert_monaco(geojson_data)

    Logger.info("Monaco successfully added to administrative divisions")
  end

  defp download_geojson do
    %Req.Response{status: 200, body: body} = Req.get!(@geojson_url)
    body |> Jason.decode!()
  end

  defp insert_monaco(geojson_data) do
    existing = DB.Repo.get_by(DB.AdministrativeDivision, type_insee: "pays_MC")

    if existing do
      Logger.info("Monaco already exists, skipping.")
    else
      {:ok, geom} = Geo.PostGIS.Geometry.cast(geojson_data)
      geom = %{geom | srid: 4326}

      %DB.AdministrativeDivision{
        type_insee: "pays_MC",
        insee: "MC",
        type: :pays,
        nom: "Monaco",
        geom: geom,
        # 2024 estimate
        population: 38_631
      }
      |> DB.Repo.insert!()
    end
  end
end
