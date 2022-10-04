defmodule DB.Repo.Migrations.SetNoumeaSiren do
  use Ecto.Migration

  def change do
    execute("UPDATE commune SET siren = '200012508' WHERE nom = 'Nouméa';")
  end
end
