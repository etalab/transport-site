defmodule DB.Repo.Migrations.CreateDatasetSubtype do
  use Ecto.Migration

  def change do
    create table(:dataset_subtype) do
      add(:parent_type, :string, null: false)
      add(:slug, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:dataset_subtype, [:parent_type, :slug]))

    create table(:dataset_dataset_subtype, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:dataset_subtype_id, references(:dataset_subtype, on_delete: :delete_all), null: false)
    end

    create(index("dataset_dataset_subtype", [:dataset_id]))
    create(index("dataset_dataset_subtype", [:dataset_subtype_id]))
  end
end
