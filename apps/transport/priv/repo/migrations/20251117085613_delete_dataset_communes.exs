defmodule DB.Repo.Migrations.DeleteDatasetCommunes do
  use Ecto.Migration

  def change do
    drop(table("dataset_communes"))
  end
end
