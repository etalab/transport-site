defmodule DB.GtfsCalendar do
  @moduledoc """
  This contains the information present in GTFS calendar.txt files.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_calendar" do
    belongs_to(:data_import, DB.GtfsImport)

    field(:service_id, :binary)
    field(:monday, :integer)
    field(:tuesday, :integer)
    field(:wednesday, :integer)
    field(:thursday, :integer)
    field(:friday, :integer)
    field(:saturday, :integer)
    field(:sunday, :integer)
    field(:days, {:array, :integer})
    field(:start_date, :date)
    field(:end_date, :date)
  end
end
