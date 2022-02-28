defmodule DB.GTFS.Calendar do
  @moduledoc """
  This contains the information present in GTFS calendar.txt files.
  https://developers.google.com/transit/gtfs/reference?hl=fr#calendartxt
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_calendar" do
    belongs_to(:data_import, DB.GTFS.Import)

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
