defmodule DB.Repo.Migrations.CreateGtfsDiffTable do
  use Ecto.Migration

  def change do
    create table(:gtfs_diff) do
      add :result_url, :text
      add :input_url_1, :text
      add :input_url_2, :text
      timestamps([type: :utc_datetime_usec])
    end
  end
end
