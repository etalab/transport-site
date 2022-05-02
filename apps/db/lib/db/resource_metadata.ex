defmodule DB.ResourceMetadata do
  @moduledoc """
  Metadata extracted from a resource.
  For example transport modes available in a GTFS file.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "resource_metadata" do
    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    belongs_to(:multi_validation, DB.MultiValidation)
    field(:metadata, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
