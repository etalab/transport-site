defmodule DB.Repo.Migrations.SetNoumeaSiren do
  use Ecto.Migration

  def up do
    execute("UPDATE commune SET siren = '200012508' WHERE nom = 'Nouméa';")
  end

  def down do
    execute("UPDATE commune SET siren = null WHERE nom = 'Nouméa';")
  end
end
