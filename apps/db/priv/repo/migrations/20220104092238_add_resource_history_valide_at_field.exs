defmodule DB.Repo.Migrations.AddResourceHistoryValideAtField do
  use Ecto.Migration

  def change do
    alter table(:resource_history) do
      add(:valide_at, :utc_datetime_usec)
    end
  end
end
