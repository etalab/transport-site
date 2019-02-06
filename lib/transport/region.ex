defmodule Transport.Region do
  @moduledoc """
  Region schema
  """
  use Ecto.Schema
  alias Transport.{AOM, Dataset}

  schema "region" do
    field :nom, :string
    field :insee, :string
    field :is_completed, :boolean
    field :geom, Geo.PostGIS.Geometry

    has_many :aoms, AOM
    has_one :datasets, Dataset
  end
end
