defmodule DB.Region do
  @moduledoc """
  Region schema

  There's a trigger on postgres on updates, it force an update of dataset
  in order to have an up-to-date search vector
  """
  use Ecto.Schema
  alias DB.{AOM, Dataset}

  schema "region" do
    field(:nom, :string)
    field(:insee, :string)
    field(:is_completed, :boolean)
    field(:geom, Geo.PostGIS.Geometry)

    has_many(:aoms, AOM)
    has_one(:datasets, Dataset)
  end
end
