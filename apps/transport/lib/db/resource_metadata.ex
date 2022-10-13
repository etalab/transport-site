defmodule DB.ResourceMetadata do
  @moduledoc """
  Metadata extracted from a resource.
  For example transport modes available in a GTFS file.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "resource_metadata" do
    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    belongs_to(:multi_validation, DB.MultiValidation)
    field(:metadata, :map)
    field(:modes, {:array, :string}, default: [])
    field(:features, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(rm in DB.ResourceMetadata, as: :metadata)

  def join_validation_with_metadata(query) do
    query
    |> join(:left, [multi_validation: mv], m in DB.ResourceMetadata, on: m.multi_validation_id == mv.id, as: :metadata)
  end

  def where_gtfs_up_to_date(query) do
    today = Date.utc_today()

    query
    |> where(
      [metadata: m],
      fragment("TO_DATE(?->>'start_date', 'YYYY-MM-DD')", m.metadata) <= ^today and
        fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) >= ^today
    )
  end
end
