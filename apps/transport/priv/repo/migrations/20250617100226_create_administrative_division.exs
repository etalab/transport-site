defmodule DB.Repo.Migrations.CreateAdministrativeDivision do
  use Ecto.Migration

  def change do
    create table(:administrative_division) do
      add(:type_insee, :string, null: false)
      add(:type, :string, null: false)
      add(:insee, :string, null: false)
      add(:nom, :string, null: false)
      add(:geom, :geometry, null: false)

      # NOTE: this table doesn’t show relationships between divisions,
      # such as communes belonging to an EPCI and a departement, etc.
    end

    create(unique_index(:administrative_division, [:type_insee]))
    create(index(:administrative_division, [:nom]))

    execute(
      """
        INSERT INTO administrative_division (type_insee, insee, type, nom, geom)
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
        WHERE NOT nom = 'National'
        UNION
        SELECT
          'pays_0' AS type_insee,
          '0' AS insee,
          'pays' AS type,
          'France' AS nom,
          ST_Union(geom) AS geom
        FROM region
        ;
      """,
      ""
    )
  end
end
