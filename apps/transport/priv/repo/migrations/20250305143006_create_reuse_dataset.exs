defmodule DB.Repo.Migrations.CreateReuseDataset do
  use Ecto.Migration

  def change do
    create table(:reuse_dataset, primary_key: false) do
      add(:reuse_id, references(:reuse, on_delete: :delete_all))
      add(:dataset_id, references(:dataset, on_delete: :delete_all))
    end
  end
end
