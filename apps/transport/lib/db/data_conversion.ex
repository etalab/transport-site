defmodule DB.DataConversion do
  @moduledoc """
  DataConversion stores metadata for data conversions from one format to another
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "data_conversion" do
    field(:convert_from, :string)
    field(:convert_to, :string)
    field(:resource_history_uuid, Ecto.UUID)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
