defmodule Transport.AOM do
  @moduledoc """
  AOM schema

  There's a trigger on postgres on updates, it force an update of dataset
  in order to have an up-to-date search vector
  """
  use Ecto.Schema
  alias Transport.{Dataset, Region, Repo}

  schema "aom" do
      field :composition_res_id, :integer
      field :insee_commune_principale, :string
      field :departement, :string
      field :siren, :integer
      field :nom, :string
      field :forme_juridique, :string
      field :nombre_communes, :integer
      field :population_muni_2014, :integer
      field :population_totale_2014, :integer
      field :surface, :string
      field :commentaire, :string
      field :geom, Geo.PostGIS.Geometry

      belongs_to :region, Region
      has_many :datasets, Dataset
      belongs_to :parent_dataset, Dataset
  end

  def get(insee_commune_principale: nil), do: nil
  def get(insee_commune_principale: insee), do: Repo.get_by(AOM, insee_commune_principale: insee)
end
