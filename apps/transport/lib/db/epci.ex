defmodule DB.EPCI do
  @moduledoc """
  EPCI schema.

  The EPCI are loaded by the task transport/lib/transport/import_epci.ex.
  The EPCI imported are only "à fiscalité propre". This excludes Etablissements Publics Territoriaux.
  This allows to have a 1 to 1 relation between a commune and an EPCI.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "epci" do
    field(:insee, :string)
    field(:nom, :string)
    field(:geom, Geo.PostGIS.Geometry) :: Geo.MultiPolygon.t()
    has_many(:communes, DB.Commune, foreign_key: :epci_insee)
  end
end
