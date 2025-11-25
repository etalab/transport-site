defmodule Mix.Tasks.Transport.PopulateAdministrativeDivisions do
  @moduledoc """
  Populates the administrative_division table with data from existing tables (commune, epci, departement, region).
  Run with `WORKER=0 mix Transport.PopulateAdministrativeDivisions`.
  """

  use Mix.Task
  require Logger

  def run(_params) do
    Logger.info("Populating administrative_division table")

    Mix.Task.run("app.start")

    # Clear existing data
    Logger.info("Clearing existing administrative divisions...")
    DB.Repo.delete_all(DB.AdministrativeDivision)

    # Insert data from all administrative tables
    Logger.info("Inserting communes...")
    insert_communes()

    Logger.info("Inserting EPCIs...")
    insert_epcis()

    Logger.info("Inserting départements...")
    insert_departements()

    Logger.info("Inserting régions...")
    insert_regions()

    Logger.info("Inserting France (pays)...")
    insert_france()

    count = DB.Repo.aggregate(DB.AdministrativeDivision, :count)
    Logger.info("Finished. Total administrative divisions: #{count}")
  end

  defp insert_communes do
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
    """)
  end

  defp insert_epcis do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom, population)
      SELECT
        CONCAT('epci_', epci.insee) AS type_insee,
        epci.insee,
        'epci' AS type,
        nom,
        geom,
        t.population
      FROM epci
      JOIN (
        SELECT epci_insee insee, sum(population) population
        FROM commune
        WHERE epci_insee is not null
        group by 1
      ) t on t.insee = epci.insee
    """)
  end

  defp insert_departements do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom, population)
      SELECT
        CONCAT('departement_', departement.insee) AS type_insee,
        departement.insee,
        'departement' AS type,
        nom,
        geom,
        t.population
      FROM departement
      JOIN (
        SELECT departement_insee insee, sum(population) population
        FROM commune
        group by 1
      ) t on t.insee = departement.insee
    """)
  end

  defp insert_regions do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom, population)
      SELECT
        CONCAT('region_', region.insee) AS type_insee,
        region.insee,
        'region' AS type,
        nom,
        geom,
        t.population
      FROM region
      JOIN (
        SELECT r.insee insee, sum(population) population
        FROM commune c
        join region r on r.id = c.region_id
        group by 1
      ) t on t.insee = region.insee
      WHERE NOT nom = 'National'
    """)
  end

  defp insert_france do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom, population)
      SELECT
        'pays_FR' AS type_insee,
        'FR' AS insee,
        'pays' AS type,
        'France' AS nom,
        ST_Union(geom) AS geom,
        min(t.population)
      FROM region
      JOIN (
        select sum(population) population
        from commune
      ) t on true
    """)
  end
end
