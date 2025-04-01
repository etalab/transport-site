defmodule DB.Repo.Migrations.CreateAdministrativeDivisionView do
  use Ecto.Migration

  def up do
    execute("""
      CREATE MATERIALIZED VIEW administrative_divisions AS
        SELECT
          CONCAT('commune_', insee) AS type_insee,
          insee,
         'commune' AS type,
          nom,
          geom
        FROM commune
      UNION
        SELECT
          CONCAT('epci_', insee) AS type_insee,
          insee,
         'epci' AS type,
          nom,
          geom
        FROM epci
      UNION
        SELECT
          CONCAT('departement_', insee) AS type_insee,
          insee,
         'departement' AS type,
          nom,
          geom
        FROM departement
      UNION
        SELECT
          CONCAT('region_', insee) AS type_insee,
          insee,
         'region' AS type,
          nom,
          geom
        FROM region
      ;
    """)

    execute("CREATE UNIQUE INDEX on administrative_divisions (type_insee);")
  end

  def down do
    execute("DROP MATERIALIZED VIEW administrative_divisions;")
  end
end
