defmodule DB.Repo.Migrations.AddGtfsAgency do
  use Ecto.Migration

  def change do
    create table(:gtfs_agency) do
      add(:data_import_id, references(:data_import, on_delete: :delete_all))
      add(:agency_id, :binary)
      add(:agency_name, :binary)
      add(:agency_url, :binary)
      add(:agency_timezone, :binary)
      add(:agency_lang, :binary)
      add(:agency_phone, :binary)
      add(:agency_fare_url, :binary)
      add(:agency_email, :binary)
      add(:cemv_support, :integer)
    end
  end
end
