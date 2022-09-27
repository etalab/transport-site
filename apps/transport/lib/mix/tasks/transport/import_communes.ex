defmodule Mix.Tasks.Transport.ImportCommunes do
  @moduledoc "Import the communes"
  @shortdoc "Refreshes the database table `commune` with the latest data"
  use Mix.Task
  import Ecto.Query
  alias Ecto.Changeset
  alias DB.{Commune, Region, Repo}
  require Logger

  @communes_geojson_url "http://etalab-datasets.geo.data.gouv.fr/contours-administratifs/2022/geojson/communes-100m.geojson"
  # See https://github.com/etalab/decoupage-administratif
  @communes_url "https://unpkg.com/@etalab/decoupage-administratif@2.2.1/data/communes.json"

  def insert_or_update_commune(
        %{
          "code" => insee,
          "nom" => nom,
          "region" => region_insee,
          "population" => population,
          "departement" => departement_insee
        } = params,
        regions,
        geojsons
      ) do
    insee
    |> get_or_create_commune()
    |> Changeset.change(%{
      insee: insee,
      nom: nom,
      region_id: Map.fetch!(regions, region_insee),
      geom: build_geometry(geojsons, insee),
      population: population,
      siren: Map.get(params, "siren"),
      arrondissement_insee: Map.get(params, "arrondissement"),
      departement_insee: departement_insee
    })
    |> Repo.insert_or_update!()
  end

  defp regions_by_insee do
    Region |> Repo.all() |> Enum.into(%{}, fn region -> {region.insee, region.id} end)
  end

  defp geojson_by_insee do
    @communes_geojson_url
    |> HTTPoison.get!(timeout: 15_000, recv_timeout: 15_000)
    |> Map.fetch!(:body)
    |> Jason.decode!()
    |> Map.fetch!("features")
    |> Enum.into(%{}, fn record -> {record["properties"]["code"], record["geometry"]} end)
  end

  defp get_or_create_commune(insee) do
    Commune
    |> Repo.get_by(insee: insee)
    |> case do
      nil ->
        %Commune{}

      commune ->
        commune
    end
  end

  defp build_geometry(geojsons, insee) do
    {:ok, geom} = Geo.PostGIS.Geometry.cast(Map.fetch!(geojsons, insee))
    %{geom | srid: 4326}
  end

  defp load_etalab_communes(region_insees) do
    @communes_url
    |> HTTPoison.get!(timeout: 15_000, recv_timeout: 15_000)
    |> Map.fetch!(:body)
    |> Jason.decode!()
    |> Enum.filter(&(&1["type"] == "commune-actuelle" and &1["region"] in region_insees))
  end

  def run(_params) do
    Logger.info("Importing communes")

    Mix.Task.run("app.start")

    regions = regions_by_insee()
    geojsons = geojson_by_insee()
    region_insees = regions |> Map.keys()

    etalab_communes = load_etalab_communes(region_insees)
    etalab_insee = etalab_communes |> Enum.map(& &1["code"])
    communes_insee = Commune |> select([c], c.insee) |> Repo.all()

    nb_new = etalab_insee |> MapSet.new() |> MapSet.difference(MapSet.new(communes_insee)) |> Enum.count()
    removed_communes = communes_insee |> MapSet.new() |> MapSet.difference(MapSet.new(etalab_insee)) |> Enum.into([])
    nb_removed = removed_communes |> Enum.count()

    Logger.info("#{nb_new} new communes")
    Logger.info("#{nb_removed} communes should be removed")

    Commune |> where([c], c.insee in ^removed_communes) |> Repo.delete_all()

    disable_trigger()
    etalab_communes |> Enum.each(&insert_or_update_commune(&1, regions, geojsons))
    Logger.info("Finished. Enabling trigger and refreshing views.")
    enable_trigger()
  end

  defp disable_trigger, do: Repo.query!("ALTER TABLE commune DISABLE TRIGGER refresh_places_commune_trigger;")

  defp enable_trigger do
    Repo.query!("ALTER TABLE commune DISABLE TRIGGER refresh_places_commune_trigger;")
    Repo.query!("REFRESH MATERIALIZED VIEW places;")
  end
end
