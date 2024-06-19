defmodule DB.Repo.Migrations.AddResourceCounterCache do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:counter_cache, :map, default: %{})
    end
  end
end
