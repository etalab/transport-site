defmodule DB.Repo.Migrations.DataImportDelete do
  use Ecto.Migration

  @gtfs_tables [
    "gtfs_stops",
    "gtfs_stop_times",
    "gtfs_trips",
    "gtfs_calendar",
    "gtfs_calendar_dates"
  ]

  def up do
    @gtfs_tables
    |> Enum.each(fn tbl ->
      alter table(tbl) do
        modify(
          :data_import_id,
          references(:data_import, on_delete: :delete_all),
          from: references(:data_import, on_delete: :nothing)
        )
      end
    end)
  end
end
