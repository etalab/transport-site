defmodule Transport.Validation do
  @moduledoc """
  Validation model
  """
  use Ecto.Schema
  alias Transport.Resource

  schema "validations" do
    field :details, :map
    field :date, :string

    belongs_to :resource, Resource
  end
end
