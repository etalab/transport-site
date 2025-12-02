defmodule DB.Commune do
  @moduledoc """
  Commune schema
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Departement, EPCI, Region}
  alias Geo.MultiPolygon

  typed_schema "commune" do
    field(:insee, :string)
    field(:nom, :string)
    field(:surf_ha, :float)
    field(:geom, Geo.PostGIS.Geometry, load_in_query: false) :: MultiPolygon.t()
    field(:population, :integer)
    field(:siren, :string)
    field(:arrondissement_insee, :string)
    field(:aom_siren, :string)

    belongs_to(:region, Region)
    belongs_to(:departement, Departement, foreign_key: :departement_insee, references: :insee, type: :string)
    belongs_to(:epci, EPCI, foreign_key: :epci_insee, references: :insee, type: :string)
  end
end
