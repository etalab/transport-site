defmodule DB.ProxyMetric do
  @moduledoc """
  A quick proxy metric schema to store bucketed events, until a moment may come
  where we'll outgrow this and use timescaledb or similar instead.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "metrics" do
    field(:resource_identifier, :string)
    field(:event, :string)
    field(:period, :utc_datetime)
    field(:count, :integer)

    timestamps(type: :utc_datetime_usec)
  end
end
