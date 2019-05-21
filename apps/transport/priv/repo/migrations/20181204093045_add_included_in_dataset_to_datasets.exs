defmodule Transport.Repo.Migrations.AddIncludedInDatasetToDatasets do
  use Ecto.Migration
  import Ecto.Query
  alias Transport.{AOM, Dataset, Region, Repo}

  def up do
    alter table(:aom) do
      add :parent_dataset_id, references ("dataset")
    end

    #flush()
    #
    #bretagne = Repo.one(from region in Region, where: region.nom == "Bretagne")
    #breizgo = Repo.one(from dataset in Dataset, where: like(dataset.title, "%MobiBreizh%"))
    #
    #if !is_nil(bretagne) and !is_nil(breizgo) do
    #  (from aom in AOM, where:
    #    aom.insee_commune_principale not in ["22050", "22070", "29024", "35360"]
    #    and aom.region_id == ^bretagne.id
    #  )
    #  |> Repo.update_all(set: [parent_dataset_id: breizgo.id])
    #end
  end

  def down do
    alter table(:aom) do
      remove :included_in
    end
  end
end
