defmodule DB.Autocomplete do
  @moduledoc """
  Autocomplete schema
  """
  use Ecto.Schema
  use TypedEctoSchema

  @primary_key false
  typed_schema "autocomplete" do
    field(:nom, :string)
    field(:type, :string)
    field(:place_id, :string)
    field(:indexed_name, :string)
  end
end
