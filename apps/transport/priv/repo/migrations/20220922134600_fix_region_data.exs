defmodule DB.Repo.Migrations.FixRegionData do
  use Ecto.Migration

  def change do
    execute "UPDATE region SET insee = '06' where nom = 'Mayotte';"
    execute "UPDATE region SET insee = '988' where nom = 'Nouvelle-Calédonie';"

    create unique_index(:region, [:insee])
    create unique_index(:region, [:nom])
  end
end
