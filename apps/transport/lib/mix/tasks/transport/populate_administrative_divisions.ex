defmodule Mix.Tasks.Transport.PopulateAdministrativeDivisions do
  @moduledoc """
  Populates the administrative_division table with data from existing tables (commune, epci, departement, region).
  Run with `mix Transport.PopulateAdministrativeDivisions`.
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
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom)
      SELECT
        CONCAT('commune_', insee) AS type_insee,
        insee,
        'commune' AS type,
        nom,
        geom
      FROM commune
    """)
  end

  defp insert_epcis do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom)
      SELECT
        CONCAT('epci_', insee) AS type_insee,
        insee,
        'epci' AS type,
        nom,
        geom
      FROM epci
    """)
  end

  defp insert_departements do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom)
      SELECT
        CONCAT('departement_', insee) AS type_insee,
        insee,
        'departement' AS type,
        nom,
        geom
      FROM departement
    """)
  end

  defp insert_regions do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom)
      SELECT
        CONCAT('region_', insee) AS type_insee,
        insee,
        'region' AS type,
        nom,
        geom
      FROM region
      WHERE NOT nom = 'National'
    """)
  end

  defp insert_france do
    DB.Repo.query!("""
      INSERT INTO administrative_division (type_insee, insee, type, nom, geom)
      SELECT
        'pays_0' AS type_insee,
        '0' AS insee,
        'pays' AS type,
        'France' AS nom,
        ST_Union(geom) AS geom
      FROM region
    """)
  end
end
