defmodule DB.EPCI do
  @moduledoc """
  EPCI schema

  Link the EPCI to some Communes.
  The EPCI are loaded once and for all by the task transport/lib/transport/import_epci.ex
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "epci" do
    field(:insee, :string)
    field(:nom, :string)
    field(:geom, Geo.PostGIS.Geometry) :: Geo.MultiPolygon.t()


    # This is now a useless field, to be deleted in a future migration
    field(:communes_insee, {:array, :string}, default: [])
  end
end
