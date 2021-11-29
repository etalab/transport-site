defmodule DB.Metrics do
  @moduledoc """
  A quick metric schema to count bucketed events, until a moment may come
  where we'll outgrow this and use timescaledb or similar instead.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "metrics" do
    field(:target, :string)
    field(:event, :string)
    field(:period, :utc_datetime)
    field(:count, :integer)

    timestamps(type: :utc_datetime_usec)
  end
end
