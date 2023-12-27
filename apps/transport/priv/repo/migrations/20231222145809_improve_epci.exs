defmodule DB.Repo.Migrations.ImproveEpci do
  use Ecto.Migration

  def change do
    rename(table(:epci), :code, to: :insee)
    create(unique_index(:epci, [:insee]))

    alter table(:commune) do
      add(:epci_insee, references(:epci, column: :insee, type: :string, on_delete: :nilify_all), null: true)
    end

    create(index(:commune, [:epci_insee]))

    # Migrate data from epci communes_insee array column to epci_insee column in commune table
    execute(
      """
        UPDATE commune
        SET epci_insee = epci.insee
        FROM epci
        WHERE commune.insee = ANY(epci.communes_insee)
      """,
      """
        UPDATE epci
        SET communes_insee = ARRAY(
          SELECT insee
          FROM commune
          WHERE commune.epci_insee = epci.insee
        )
      """
    )

    alter table(:epci) do
      add(:geom, :geometry)
      remove(:communes_insee, {:array, :string}, default: [])
    end
  end
end
