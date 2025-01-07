defmodule DatasetTerritory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "dataset_territories" do
    belongs_to(:dataset, DB.Dataset)
    belongs_to(:commune, DB.Commune)
    belongs_to(:epci, DB.EPCI)
    belongs_to(:departement, DB.Departement)
    belongs_to(:region, DB.Region)

    timestamps()
  end

  @doc false
  #  def changeset(%DatasetTerritery{} = dataset_territery, attrs) do
  #    dataset_territery
  #    |> cast(attrs, [::dataset_id, ::commune_id, ::epci_id, ::departement_id, ::region_id])
  #    |> validate_required([:dataset_id])
  #  end
end
