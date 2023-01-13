defmodule DB.GTFSDiff do
  @moduledoc """
  Table storing GTFS Diff requests and output
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_diff" do
    field(:result_url, :string)
    field(:input_1, :map)
    field(:input_2, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
