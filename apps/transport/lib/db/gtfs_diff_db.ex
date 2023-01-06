defmodule DB.GTFSDiff do
  @moduledoc """
  Table storing GTFS Diff requests and output
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_diff" do
    field(:result_url, :string)
    field(:input_url_1, :string)
    field(:input_url_2, :string)

    timestamps(type: :utc_datetime_usec)
  end
end
