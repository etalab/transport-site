defmodule DB.GtfsImport do
  @moduledoc """
  GtfsImport list the imports done for each Resource History.
  It will be a good place to add information about which import is currently in use, publishesd, etc
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_import" do
    belongs_to(:resource_history, DB.ResourceHistory)
  end
end
