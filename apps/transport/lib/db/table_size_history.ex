defmodule DB.TableSizeHistory do
  @moduledoc """
  History table holding table size records
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "table_size_history" do
    field(:table_name, :string)
    field(:size, :integer)
    field(:date, :date)
  end
end
