defmodule DB.Commune do
  @moduledoc """
  Commune schema
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{AOM, Departement, Region}
  alias Geo.MultiPolygon

  typed_schema "commune" do
    field(:insee, :string)
    field(:nom, :string)
    field(:surf_ha, :float)
    field(:geom, Geo.PostGIS.Geometry) :: MultiPolygon.t()
    field(:population, :integer)
    field(:siren, :string)
    field(:arrondissement_insee, :string)

    belongs_to(:aom_res, AOM, references: :composition_res_id)
    belongs_to(:region, Region)
    belongs_to(:departement, Departement, foreign_key: :departement_insee, references: :insee, type: :string)
  end
end
