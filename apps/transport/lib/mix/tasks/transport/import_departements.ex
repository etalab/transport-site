defmodule Mix.Tasks.Transport.ImportDepartements do
  @moduledoc """
  Import the departements
  """
  use Mix.Task
  import Ecto.Query
  alias Ecto.Changeset
  alias DB.{Departement, Repo}
  require Logger

  @departements_geojson_url "http://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/departements-100m.geojson"
  # See https://github.com/etalab/decoupage-administratif
  @departements_url "https://unpkg.com/@etalab/decoupage-administratif@2.2.1/data/departements.json"

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
    |> Repo.insert_or_update!()
  end

  defp geojson_by_insee do
    @departements_geojson_url
    |> HTTPoison.get!(timeout: 15_000, recv_timeout: 15_000)
    |> Map.fetch!(:body)
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
    {:ok, geom} = Geo.PostGIS.Geometry.cast(Map.fetch!(geojsons, insee))
    %{geom | srid: 4326}
  end

  defp load_etalab_departements do
    @departements_url
    |> HTTPoison.get!(timeout: 15_000, recv_timeout: 15_000)
    |> Map.fetch!(:body)
    |> Jason.decode!()
    |> Enum.filter(&(&1["zone"] in ["metro", "drom"] or &1["nom"] == "Nouvelle-Calédonie"))
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

    Departement |> where([c], c.insee in ^removed_departements) |> Repo.delete_all()

    etalab_departements |> Enum.each(&insert_or_update_departement(&1, geojsons))
  end
end
