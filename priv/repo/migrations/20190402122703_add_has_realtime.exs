defmodule Transport.Repo.Migrations.AddHasRealtime do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add :has_realtime, :boolean, default: false
    end
  end
end
