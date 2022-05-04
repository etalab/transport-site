defmodule DB.Repo.Migrations.Features do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:features, {:array, :string}, default: [])
    end
    rename(table(:resource), :auto_tags, to: :modes)
  end
end
