defmodule DB.Repo.Migrations.RegionRemoveIsCompleted do
  use Ecto.Migration

  def change do
    alter table(:region) do
      remove(:is_completed)
    end
  end
end
