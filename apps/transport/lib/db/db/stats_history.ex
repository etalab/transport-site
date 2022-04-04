defmodule DB.StatsHistory do
  @moduledoc """
  Store key metrics as time series
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "stats_history" do
    field(:timestamp, :utc_datetime)
    field(:metric, :string)
    field(:value, :decimal)
  end
end
