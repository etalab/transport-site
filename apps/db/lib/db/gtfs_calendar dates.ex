defmodule DB.GtfsCalendarDates do
  @moduledoc """
  This contains the information present in GTFS calendar_dates.txt files.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_calendar_dates" do
    belongs_to(:data_import, DB.GtfsImport)

    field(:service_id, :binary)
    field(:date, :date)
    field(:exception_type, :integer)
  end
end
