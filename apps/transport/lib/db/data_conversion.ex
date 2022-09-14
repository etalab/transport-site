defmodule DB.DataConversion do
  @moduledoc """
  DataConversion stores metadata for data conversions from one format to another
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "data_conversion" do
    field(:convert_from, :string)
    field(:convert_to, :string)
    field(:resource_history_uuid, Ecto.UUID)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(dc in DB.DataConversion, as: :data_conversion)

  def join_resource_history_with_data_conversion(query, list_of_convert_to) do
    query
    |> join(:left, [resource_history: rh], dc in DB.DataConversion,
      on: fragment("?->>'uuid' = ?.resource_history_uuid::text", rh.payload, dc),
      as: :data_conversion
    )
    |> where([data_conversion: dc], dc.convert_to in ^list_of_convert_to)
  end
end
