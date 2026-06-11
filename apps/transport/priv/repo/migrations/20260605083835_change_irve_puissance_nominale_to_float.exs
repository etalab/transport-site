defmodule DB.Repo.Migrations.ChangeIrvePuissanceNominaleToFloat do
  use Ecto.Migration

  def change do
    alter table(:irve_valid_pdc) do
      modify(:puissance_nominale, :float, from: :decimal)
    end
  end
end
