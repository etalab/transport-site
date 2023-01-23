defmodule DB.Repo.Migrations.DatasetAddUniqueDatagouvId do
  use Ecto.Migration

  def change do
    create_if_not_exists(unique_index(:dataset, [:datagouv_id]))
  end
end
