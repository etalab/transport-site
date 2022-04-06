defmodule DB.Repo.Migrations.AddGeoData do
  use Ecto.Migration

  def change do
    create table(:geo_data) do
      add :geom, :geometry
      add :payload, :map
      add :geo_data_import_id, references(:geo_data, on_delete: :delete_all)

    end

    create table(:geo_data_import) do
      add :resource_history_id, references(:resource_history)
      add :publish, :boolean
    end
  end
end
