defmodule DB.GTFS.Trips do
  @moduledoc """
  This contains the information present in GTFS trips.txt files.
  https://developers.google.com/transit/gtfs/reference?hl=fr#tripstxt
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_trips" do
    belongs_to(:data_import, DB.GTFS.Import)

    field(:route_id, :binary)
    field(:service_id, :binary)
    field(:trip_id, :binary)
  end
end
