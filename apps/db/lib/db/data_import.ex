defmodule DB.DataImport do
  @moduledoc """
  Table linking a ResourceHistory with a DataImport.
  A DataImport is for example the import of a GTFS file to the DB.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "data_import" do
    belongs_to(:resource_history, DB.ResourceHistory)
    timestamps(type: :utc_datetime_usec)
  end
end
