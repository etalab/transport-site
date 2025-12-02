defmodule DB.Repo.Migrations.RegionRemoveIsCompleted do
  use Ecto.Migration

  def change do
    alter table(:region) do
      drop(:is_completed)
    end
  end
end
