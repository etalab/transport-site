defmodule DB.Repo.Migrations.CreateGtfsDiffTable do
  use Ecto.Migration

  def change do
    create table(:gtfs_diff) do
      add :result_url, :text
      add :input_1, :jsonb
      add :input_2, :jsonb
      timestamps([type: :utc_datetime_usec])
    end
  end
end
