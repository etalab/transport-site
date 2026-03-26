defmodule Mix.Tasks.Transport.AddSwitzerland do
  @moduledoc """
  Adds Switzerland as a country to the administrative_division table.
  Run with `mix Transport.AddSwitzerland`.
  """
  use Mix.Task
  require Logger

  @geojson_url "https://geo2day.com/europe/switzerland.geojson"

  def run(_params) do
    Logger.info("Adding Switzerland to administrative_division table")

    Mix.Task.run("app.start")

    Logger.info("Downloading Switzerland GeoJSON...")
    %{"features" => [%{"geometry" => geojson_data}]} = download_geojson()

    Logger.info("Inserting Switzerland...")
    insert_switzerland(geojson_data)

    Logger.info("Switzerland successfully added to administrative divisions")
  end

  defp download_geojson do
    %Req.Response{status: 200, body: body} = Req.get!(@geojson_url)
    body |> Jason.decode!()
  end

  defp insert_switzerland(geojson_data) do
    existing = DB.Repo.get_by(DB.AdministrativeDivision, type_insee: "pays_CH")

    if existing do
      Logger.info("Switzerland already exists, skipping.")
    else
      {:ok, geom} = Geo.PostGIS.Geometry.cast(geojson_data)
      geom = %{geom | srid: 4326}

      %DB.AdministrativeDivision{
        type_insee: "pays_CH",
        insee: "MC",
        type: :pays,
        nom: "Switzerland",
        geom: geom,
        # 2024 estimate
        population: 8_981_565
      }
      |> DB.Repo.insert!()
    end
  end
end
