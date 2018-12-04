defmodule Transport.AOM do
  @moduledoc """
  AOM schema
  """
  use Ecto.Schema
  alias Transport.{Dataset, Region}

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
      field :geometry, :map

      belongs_to :region, Region
      has_many :datasets, Dataset
      belongs_to :global_dataset, Dataset
  end
end
