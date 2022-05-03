defmodule DB.Repo.Migrations.SlugConstraint do
  use Ecto.Migration

  def change do
    create(unique_index(:dataset, [:slug]))
  end
end
