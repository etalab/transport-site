defmodule DB.Repo.Migrations.AddIndices do
  use Ecto.Migration

  def change do
    # add some indices to speed up the stats query
    create(index(:resource, [:format, :dataset_id]))
    create(index(:dataset, [:aom_id]))
  end
end
