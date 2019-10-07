defmodule DB.Repo.Migrations.AddDatasetActivation do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
        add :is_active, :boolean, default: true
    end
  end
end
