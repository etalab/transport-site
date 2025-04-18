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

  test "changeset" do
    departement = insert(:departement)
    commune = insert(:commune, departement: departement)

    assert {:ok, changeset} =
             DB.Dataset.changeset(%{
               "datagouv_id" => "12345079",
               "custom_title" => "Blaaah",
               "datagouv_title" => "title",
               "type" => "public-transit",
               "licence" => "lov2",
               "slug" => "ma_limace",
               "created_at" => DateTime.utc_now(),
               "last_update" => DateTime.utc_now(),
               "logo" => "https://example.com/pic.jpg",
               "full_logo" => "https://example.com/pic.jpg",
               "frequency" => "daily",
               "new_covered_areas" => [
                 %{
                   "administrative_division_type" => "commune",
                   "commune_id" => commune.id
                 }
               ],
               "region_id" => 1,
               "organization_id" => Ecto.UUID.generate(),
               "tags" => [],
               "nb_reuses" => 0
             })

    {:ok, dataset} = changeset |> DB.Repo.insert()

    dataset = dataset |> DB.DatasetNewCoveredArea.preload_covered_area_objects()

    [area] = dataset.new_covered_areas

    assert area.commune_id == commune.id
    assert area.nom == commune.nom
  end
end
