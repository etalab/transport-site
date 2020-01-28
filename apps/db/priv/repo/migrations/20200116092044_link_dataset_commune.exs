defmodule DB.Repo.Migrations.LinkDatasetCommune do
  use Ecto.Migration

  def change do
    create table(:dataset_communes, primary_key: false) do
      add(:dataset_id, references(:dataset), on_delete: :delete_all)
      add(:commune_id, references(:commune), on_delete: :delete_all)
    end
  end
end
