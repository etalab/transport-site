defmodule DB.AOM do
  @moduledoc """
  AOM schema

  There's a trigger on postgres on updates, it force an update of dataset
  in order to have an up-to-date search vector
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, Departement, Region, Repo}
  alias Geo.MultiPolygon

  typed_schema "aom" do
    field(:insee_commune_principale, :string)
    field(:siren, :string)
    field(:nom, :string)
    field(:forme_juridique, :string)
    field(:nombre_communes, :integer)
    field(:population, :integer)
    field(:surface, :string)
    field(:geom, Geo.PostGIS.Geometry, load_in_query: false) :: MultiPolygon.t()

    belongs_to(:region, Region)
    belongs_to(:departement_object, Departement, foreign_key: :departement, references: :insee, type: :string)

    many_to_many(:legal_owners_dataset, Dataset, join_through: "dataset_aom_legal_owner")
  end

  @spec get(insee_commune_principale: binary()) :: __MODULE__ | nil
  def get(insee_commune_principale: nil), do: nil
  def get(insee_commune_principale: insee), do: Repo.get_by(AOM, insee_commune_principale: insee)
end
