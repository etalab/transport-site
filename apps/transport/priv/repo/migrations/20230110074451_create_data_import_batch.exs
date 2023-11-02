defmodule DB.Repo.Migrations.CreateDataImportBatch do
  use Ecto.Migration

  def change do
    create table("data_import_batch") do
      add(:summary, :map, default: %{})
      timestamps(type: :utc_datetime_usec)
    end
  end
end
