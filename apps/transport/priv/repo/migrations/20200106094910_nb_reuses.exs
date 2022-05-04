defmodule DB.Repo.Migrations.NbReuses do
  use Ecto.Migration
  require Logger

  def change do
    alter table(:dataset) do
      add(:nb_reuses, :integer)
    end
  end
end
