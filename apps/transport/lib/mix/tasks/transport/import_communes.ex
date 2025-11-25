defmodule Mix.Tasks.Transport.ImportCommunes do
  @moduledoc """
  Import or updates commune data (list, geometry) from official sources.
  Run with `mix Transport.ImportCommunes`.
  """
  @shortdoc "Refreshes the database table `commune` with the latest data"
  use Mix.Task
  import Ecto.Query
  alias DB.{Commune, Region, Repo}
  alias Ecto.Changeset
  require Logger

  # List of communes with their geometry, but lacking additional information
  @communes_geojson_url "http://etalab-datasets.geo.data.gouv.fr/contours-administratifs/2025/geojson/communes-100m.geojson"
  # List of official communes with additional information (population, arrondissement, etc.)
  # See https://github.com/etalab/decoupage-administratif
  @communes_url "https://unpkg.com/@etalab/decoupage-administratif@5.0.2/data/communes.json"

  @doc "Loads regions from the database and returns a list of tuples with INSEE code and id"
  def regions_by_insee do
    Region |> Repo.all() |> Enum.into(%{}, fn region -> {region.insee, region.id} end)
  end

  @doc "Loads GeoJSON data from the official source and returns a list of tuples with INSEE code and geometry"
  def geojson_by_insee do
    %{status: 200, body: body} =
      Req.get!(@communes_geojson_url, connect_options: [timeout: 15_000], receive_timeout: 15_000)

    body
    # Req doesn’t decode GeoJSON body automatically as it does for JSON
    |> Jason.decode!()
    |> Map.fetch!("features")
    |> Enum.into(%{}, fn record -> {record["properties"]["code"], record["geometry"]} end)
  end

  @doc """
  Loads communes from the official network source and returns a list of communes as maps.
  Result is filtered, we only get:
  - Current communes (there may have been communes deletions)
  - Communes from the regions we have in the database
  """
  def load_etalab_communes(region_insees) do
    %{status: 200, body: body} = Req.get!(@communes_url, connect_options: [timeout: 15_000], receive_timeout: 15_000)

    body
    |> Enum.filter(&(&1["type"] == "commune-actuelle" and &1["region"] in region_insees))
  end

  @doc """
  First creates the commune (without geometry) if it doesn’t exist.
  Then updates the commune with the new data through a changeset.
  Returns a list of keys of changed fields for statistics.
  """
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
    changeset =
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

    changeset_change_keys = changeset.changes |> Map.keys()

    unless Enum.empty?(changeset_change_keys -- [:geom, :population]) do
      Logger.info("Important changes for INSEE #{changeset.data.insee}. #{readable_changeset(changeset)}")
    end

    changeset |> Repo.insert_or_update!()
    changeset_change_keys
  end

  # See https://github.com/datagouv/decoupage-administratif/issues/49 for the 3 communes below
  # Population taken on Wikipedia, 2021
  def insert_or_update_commune(%{"code" => "60694", "nom" => "Les Hauts-Talican"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 543), regions, geojsons)

  def insert_or_update_commune(%{"code" => "85165", "nom" => "L'Oie"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 1259), regions, geojsons)

  def insert_or_update_commune(%{"code" => "85212", "nom" => "Sainte-Florence"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 1333), regions, geojsons)

  def insert_or_update_commune(%{"code" => "12218", "nom" => "Conques-en-Rouergue"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 1_555), regions, geojsons)

  def insert_or_update_commune(%{"code" => "14581", "nom" => "Aurseulles"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 1_908), regions, geojsons)

  def insert_or_update_commune(%{"code" => "15031", "nom" => "Celles"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 25), regions, geojsons)

  def insert_or_update_commune(%{"code" => "15035", "nom" => "Chalinargues"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 311), regions, geojsons)

  def insert_or_update_commune(%{"nom" => "Chavagnac"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 91), regions, geojsons)

  def insert_or_update_commune(%{"nom" => "Sainte-Anastasie"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 124), regions, geojsons)

  def insert_or_update_commune(%{"nom" => "Orée d'Anjou"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 16_975), regions, geojsons)

  def insert_or_update_commune(%{"nom" => "Porte des Pierres Dorées"} = params, regions, geojsons),
    do: insert_or_update_commune(params |> Map.put("population", 4_079), regions, geojsons)

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
    # Consider using `ST_MakeValid when it will be available
    # https://github.com/bryanjos/geo_postgis/pull/146
    {:ok, geom} = Geo.PostGIS.Geometry.cast(Map.fetch!(geojsons, insee))
    %{geom | srid: 4326}
  end

  defp readable_changeset(%Ecto.Changeset{changes: changes, data: data}) do
    changes
    |> Map.keys()
    |> Enum.map_join(" ; ", fn key -> "#{key}: #{Map.get(data, key)} => #{Map.get(changes, key)}" end)
  end

  def run(_params) do
    Logger.info("Importing communes")

    Mix.Task.run("app.start")

    # Gets a list of tuples describing regions from the database
    regions = regions_by_insee()
    region_insees = regions |> Map.keys()
    # Gets a list of tuples describing communes GeoJSON from the network
    geojsons = geojson_by_insee()
    # Gets the official list of communes from the network and filter them to match database regions
    etalab_communes = load_etalab_communes(region_insees)
    etalab_insee = etalab_communes |> Enum.map(& &1["code"])
    # Loads current communes INSEE list from the database
    communes_insee = Commune |> select([c], c.insee) |> Repo.all()

    new_communes = etalab_insee |> MapSet.new() |> MapSet.difference(MapSet.new(communes_insee))
    nb_new = new_communes |> Enum.count()
    removed_communes = communes_insee |> MapSet.new() |> MapSet.difference(MapSet.new(etalab_insee)) |> Enum.into([])
    nb_removed = removed_communes |> Enum.count()

    Logger.info("#{nb_new} new communes. INSEE codes: #{Enum.join(new_communes, ", ")}")
    Logger.info("#{nb_removed} communes should be removed. INSEE codes: #{Enum.join(removed_communes, ", ")}")

    Logger.info("Deleting removed communes…")
    Commune |> where([c], c.insee in ^removed_communes) |> Repo.delete_all()

    Logger.info("Updating communes (including potentially incorrect geometry)…")
    # Inserts new communes, updates existing ones (mainly geometry, but also names…)
    changelist = etalab_communes |> Enum.map(&insert_or_update_commune(&1, regions, geojsons))
    Logger.info("Finished. Count of changes: #{inspect(changelist |> List.flatten() |> Enum.frequencies())}")

    Logger.info("Ensure valid geometries and rectify if needed.")
    ensure_valid_geometries()

    Logger.info("Updating administrative_division.")
    update_administrative_division()
  end

  defp ensure_valid_geometries,
    do: Repo.query!("UPDATE commune SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);")

  def update_administrative_division do
    DB.Repo.query!("""
      DELETE
      FROM administrative_division
      WHERE type = 'commune' AND insee NOT IN (SELECT insee FROM commune);
    """)

    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom, population)
      SELECT
        CONCAT('commune_', insee) AS type_insee,
        insee,
        'commune' AS type,
        nom,
        geom,
        population
      FROM commune
      WHERE insee NOT IN (select insee from administrative_division where type = 'commune')
    """)
  end
end
