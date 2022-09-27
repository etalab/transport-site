defmodule DB.Departement do
  @moduledoc """
  Departement schema
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "departement" do
    field(:insee, :string)
    field(:nom, :string)
    field(:geom, Geo.PostGIS.Geometry) :: Geo.MultiPolygon.t()
    field(:zone, :string)

    belongs_to(:region, DB.Region, foreign_key: :region_insee, references: :insee, type: :string)
    belongs_to(:prefecture, DB.Commune, foreign_key: :chef_lieu, references: :insee, type: :string)
  end
end
