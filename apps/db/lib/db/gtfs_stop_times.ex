defmodule DB.GtfsStopTimes do
  @moduledoc """
  This contains the information present in GTFS stops.txt files.
  https://developers.google.com/transit/gtfs/reference?hl=fr#stop_timestxt
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_stop_times" do
    belongs_to(:data_import, DB.GtfsImport)
    field(:trip_id, :binary)
    field(:stop_id, :binary)
    field(:stop_sequence, :integer)
    field(:arrival_time, EctoInterval)
    field(:departure_time, EctoInterval)
  end
end
