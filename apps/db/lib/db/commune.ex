defmodule DB.Commune do
  @moduledoc """
  Commune schema
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.AOM
  alias Geo.MultiPolygon

  typed_schema "commune" do
    field(:insee, :string)
    field(:nom, :string)
    field(:wikipedia, :string)
    field(:surf_ha, :float)
    field(:geom, Geo.PostGIS.Geometry) :: MultiPolygon.t()

    belongs_to(:aom_res, AOM, references: :composition_res_id)
  end
end
