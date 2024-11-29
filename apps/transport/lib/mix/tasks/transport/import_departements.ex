defmodule Mix.Tasks.Transport.ImportDepartements do
  @moduledoc "Import the departements"
  @shortdoc "Refreshes the database table `departement` with the latest data"

  use Mix.Task
  import Ecto.Query
  alias Ecto.Changeset
  alias DB.{Departement, Repo}
  require Logger

  @departements_geojson_url "http://etalab-datasets.geo.data.gouv.fr/contours-administratifs/2024/geojson/departements-100m.geojson"
  # See https://github.com/etalab/decoupage-administratif
  @departements_url "https://unpkg.com/@etalab/decoupage-administratif@4.0.0/data/departements.json"

  def insert_or_update_departement(
        %{
          "code" => insee,
          "region" => region,
          "chefLieu" => chef_lieu,
          "nom" => nom,
          "zone" => zone
        },
        geojsons
      ) do
    changeset =
      insee
      |> get_or_create_departement()
      |> Changeset.change(%{
        insee: insee,
        region_insee: region,
        chef_lieu: chef_lieu,
        nom: nom,
        zone: zone,
        geom: build_geometry(geojsons, insee)
      })

    changeset_change_keys = changeset.changes |> Map.keys()

    unless Enum.empty?(changeset_change_keys -- [:geom, :population]) do
      Logger.info("Important changes for INSEE #{insee}. #{readable_changeset(changeset)}")
    end

    changeset |> Repo.insert_or_update!()
    changeset_change_keys
  end

  defp geojson_by_insee do
    %{status: 200, body: body} =
      Req.get!(@departements_geojson_url, connect_options: [timeout: 15_000], receive_timeout: 15_000)

    body
    # Req doesn’t decode GeoJSON body automatically as it does for JSON
    |> Jason.decode!()
    |> Map.fetch!("features")
    |> Enum.into(%{}, fn record -> {record["properties"]["code"], record["geometry"]} end)
  end

  defp get_or_create_departement(insee) do
    Departement
    |> Repo.get_by(insee: insee)
    |> case do
      nil ->
        %Departement{}

      departement ->
        departement
    end
  end

  defp build_geometry(geojsons, insee) do
    # Consider using `ST_MakeValid` when it will be available
    # https://github.com/bryanjos/geo_postgis/pull/146
    {:ok, geom} = Geo.PostGIS.Geometry.cast(Map.fetch!(geojsons, insee))
    %{geom | srid: 4326}
  end

  defp load_etalab_departements do
    %{status: 200, body: body} =
      Req.get!(@departements_url, connect_options: [timeout: 15_000], receive_timeout: 15_000)

    body
    |> Enum.filter(&(&1["zone"] in ["metro", "drom"] or &1["nom"] == "Nouvelle-Calédonie"))
  end

  defp readable_changeset(%Ecto.Changeset{changes: changes, data: data}) do
    changes
    |> Map.keys()
    |> Enum.map_join(" ; ", fn key -> "#{key}: #{Map.get(data, key)} => #{Map.get(changes, key)}" end)
  end

  def run(_params) do
    Logger.info("Importing departements")

    Mix.Task.run("app.start")

    geojsons = geojson_by_insee()

    etalab_departements = load_etalab_departements()
    etalab_insee = etalab_departements |> Enum.map(& &1["code"])
    departements_insee = Departement |> select([c], c.insee) |> Repo.all()

    nb_new = etalab_insee |> MapSet.new() |> MapSet.difference(MapSet.new(departements_insee)) |> Enum.count()

    removed_departements =
      departements_insee |> MapSet.new() |> MapSet.difference(MapSet.new(etalab_insee)) |> Enum.into([])

    nb_removed = removed_departements |> Enum.count()

    Logger.info("#{nb_new} new departements")
    Logger.info("#{nb_removed} departements should be removed")

    Logger.info("Deleting removed communes…")
    Departement |> where([c], c.insee in ^removed_departements) |> Repo.delete_all()

    Logger.info("Updating departments (including potentially incorrect geometry)…")
    changelist = etalab_departements |> Enum.map(&insert_or_update_departement(&1, geojsons))
    Logger.info("Finished. Count of changes: #{inspect(changelist |> List.flatten() |> Enum.frequencies())}")
    Logger.info("Ensure valid geometries and rectify if needed.")
    ensure_valid_geometries()
  end

  defp ensure_valid_geometries,
    do: Repo.query!("UPDATE departement SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);")
end
