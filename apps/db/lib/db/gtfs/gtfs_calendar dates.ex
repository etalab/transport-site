defmodule DB.GTFS.CalendarDates do
  @moduledoc """
  This contains the information present in GTFS calendar_dates.txt files.
  https://developers.google.com/transit/gtfs/reference?hl=fr#calendar_datestxt
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_calendar_dates" do
    belongs_to(:data_import, DB.GTFS.Import)

    field(:service_id, :binary)
    field(:date, :date)
    field(:exception_type, :integer)
  end
end
