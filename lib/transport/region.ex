defmodule Transport.Region do
  @moduledoc """
  Region schema
  """
  use Ecto.Schema
  alias Transport.{AOM, Dataset}

  schema "region" do
    field :nom, :string
    field :insee, :string
    field :geometry, :map
    field :is_completed, :boolean

    has_many :aoms, AOM
    has_one :datasets, Dataset
  end
  use ExConstructor
end
