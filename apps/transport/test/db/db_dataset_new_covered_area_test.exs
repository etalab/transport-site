defmodule DB.DatasetNewCoveredAreaTest do
  @moduledoc """
  Tests specific to Dataset Covered area
  """
  use DB.DatabaseCase, cleanup: [:datasets]
  use Oban.Testing, repo: DB.Repo
  alias DB.Repo
  import DB.Factory

  describe "territories" do
    @tag :focus
    test "read them" do
      departement = insert(:departement)
      commune = insert(:commune, departement: departement)
      dataset = insert(:dataset, departements: [departement], new_communes: [commune])
      dataset = dataset |> DB.DatasetNewCoveredArea.populate_covered_area()
      assert dataset.covered_area == [
        %{id: departement.id, insee: departement.insee, nom: departement.nom, type: "departement"},
        %{id: commune.id, insee: commune.insee, nom: commune.nom, type: "commune"}]
    end

    test "create new dataset with covered area" do
      departement = insert(:departement)
      commune = insert(:commune, departement: departement)
      departement_count = DB.Departement |> DB.Repo.aggregate(:count)

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
                 # TODO: change it so it works through the abstraction
                 "departements" => [departement.insee],
                 "new_communes" => [commune.insee],
                 "region_id" => 1,
                 "organization_id" => Ecto.UUID.generate(),
                 "tags" => [],
                 "nb_reuses" => 0
               })

      {:ok, dataset} = changeset |> DB.Repo.insert()

      [associated_departement] = dataset.departements
      assert associated_departement.id == departement.id
      [associated_commune] = dataset.new_communes
      assert associated_commune.id == commune.id
      assert DB.Departement |> DB.Repo.aggregate(:count) == departement_count
    end
  end

  test "edit existing dataset covered area" do
    # Note: here we need to have preloaded existing covered area, else the put_assoc doesn’t work
    # While the creation works without.
    departement = insert(:departement)
    commune = insert(:commune)
    dataset = insert(:dataset, departements: [departement])

    assert {:ok, changeset} =
             DB.Dataset.changeset(%{
               "dataset_id" => dataset.id,
               "departements" => [],
               "new_communes" => [commune.insee]
             })

    {:ok, dataset} = changeset |> DB.Repo.update()

    assert [] == dataset.departements
    assert [commune] == dataset.new_communes
  end
end
