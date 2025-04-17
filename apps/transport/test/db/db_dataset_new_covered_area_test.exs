defmodule DB.DatasetNewCoveredAreaTest do
  @moduledoc """
  Tests on the Dataset schema
  """
  use DB.DatabaseCase, cleanup: [:datasets]
  use Oban.Testing, repo: DB.Repo
  alias DB.Repo
  import DB.Factory

  test "Read" do
    # Create a dataset
    dataset = insert(:dataset)

    # Create a departement
    departement = insert(:departement)

    # Insert a new covered area with the departement
    %DB.DatasetNewCoveredArea{
      dataset_id: dataset.id,
      departement_id: departement.id,
      administrative_division_type: :departement
    }
    |> Repo.insert!()

    dataset =
      Repo.get!(DB.Dataset, dataset.id)
      |> DB.DatasetNewCoveredArea.preload_covered_area_objects()

    [%DB.DatasetNewCoveredArea{} = covered_area] = dataset.new_covered_areas

    assert covered_area.nom == departement.nom
  end
end
