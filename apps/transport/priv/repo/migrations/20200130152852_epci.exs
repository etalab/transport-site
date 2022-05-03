defmodule DB.Repo.Migrations.Epci do
  use Ecto.Migration

  def change do
    create table(:epci) do
      add :code, :string
      add :nom, :string
      add :communes_insee, {:array, :string}
    end

  end
end
