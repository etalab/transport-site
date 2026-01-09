defmodule Mix.Tasks.Transport.UpdateFranceGeoJSON do
  @moduledoc """
  Update France's geometry in administrative_division.
  Run with `mix Transport.UpdateFranceGeoJSON`.
  """
  use Mix.Task
  require Logger

  @geojson_url "https://raw.githubusercontent.com/gregoiredavid/france-geojson/refs/heads/master/metropole-version-simplifiee.geojson"

  def run(_params) do
    Mix.Task.run("app.start")

    Logger.info("Downloading GeoJSON…")
    %{"geometry" => geojson_data} = download_geojson()

    update_france_geom(geojson_data)

    Logger.info("France's geom has been updated")
  end

  defp download_geojson do
    %Req.Response{status: 200, body: body} = Req.get!(@geojson_url)
    body |> Jason.decode!()
  end

  defp update_france_geom(geojson_data) do
    {:ok, geom} = Geo.PostGIS.Geometry.cast(geojson_data)
    geom = %{geom | srid: 4326}

    DB.Repo.get_by(DB.AdministrativeDivision, type_insee: "pays_FR")
    |> Ecto.Changeset.change(%{geom: geom})
    |> DB.Repo.update!()
  end
end
