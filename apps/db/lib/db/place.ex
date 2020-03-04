defmodule DB.Place do
  @moduledoc """
  Commune schema
  """
  use Ecto.Schema
  use TypedEctoSchema

  @primary_key false
  typed_schema "places" do
    field(:nom, :string)
    field(:type, :string)
    field(:place_id, :string)
    field(:indexed_name, :string)
  end
end
