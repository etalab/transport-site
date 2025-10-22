defmodule DB.Region do
  @moduledoc """
  Region schema

  There's a trigger on postgres on updates, it force an update of dataset
  in order to have an up-to-date search vector
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{AOM, Departement}
  alias Geo.MultiPolygon

  typed_schema "region" do
    field(:nom, :string)
    field(:insee, :string)
    field(:is_completed, :boolean)
    field(:geom, Geo.PostGIS.Geometry) :: MultiPolygon.t()

    has_many(:aoms, AOM)
    has_many(:departements, Departement, foreign_key: :region_insee, references: :insee)
  end

  def national, do: DB.Repo.get_by!(DB.Region, nom: "National")
end
