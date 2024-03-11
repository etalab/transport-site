defmodule DB.Repo.Migrations.CreateDatasetsFollowers do
  use Ecto.Migration

  def change do
    create table(:dataset_followers) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:contact_id, references(:contact, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:dataset_followers, [:dataset_id, :contact_id]))
  end
end
