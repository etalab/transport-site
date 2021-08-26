defmodule DB.DatasetDBTest do
  @moduledoc """
  Tests on the Dataset schema
  """
  use DB.DatabaseCase, cleanup: [:datasets]
  alias DB.Repo
  import DB.Factory

  test "delete_parent_dataset" do
    parent_dataset = Repo.insert!(%Dataset{})
    linked_aom = Repo.insert!(%AOM{parent_dataset_id: parent_dataset.id, nom: "Jolie AOM"})

    # linked_aom is supposed to have a parent_dataset id
    assert not is_nil(linked_aom.parent_dataset_id)

    # it should be possible to delete a dataset even if it is an AOM's parent dataset
    Repo.delete!(parent_dataset)

    # after parent deletion, the aom should have a nil parent_dataset
    linked_aom = Repo.get!(AOM, linked_aom.id)
    assert is_nil(linked_aom.parent_dataset_id)
  end

  test "delete dataset associated to a commune" do
    commune = insert(:commune)

    dataset =
      :dataset
      |> insert()
      |> Repo.preload(:communes)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:communes, [commune])
      |> Repo.update!()

    # check the assoc succeeded
    [associated_commune] = dataset.communes
    assert associated_commune.id == commune.id

    # the deletion will raise if no on_delete action is defined because of the presence of a foreign key
    Repo.delete!(dataset)
  end

  describe "changeset of a dataset" do
    test "empty params are rejected" do
      assert {:error, _} = Dataset.changeset(%{})
    end

    test "slug is required" do
      assert {:error, _} = Dataset.changeset(%{"datagouv_id" => "1"})
    end

    test "some geographic link is required" do
      assert {:error, _} = Dataset.changeset(%{"datagouv_id" => "1", "slug" => "ma_limace"})
    end

    test "with insee code of a commune linked to an aom, it works" do
      assert {:ok, _} = Dataset.changeset(%{"datagouv_id" => "1", "slug" => "ma_limace", "insee" => "38185"})
    end

    test "with datagouv_zone only, it fails" do
      assert {:error, _} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "slug" => "ma_limace",
                 "zones" => ["38185"]
               })
    end

    test "with datagouv_zone and territory name, it works" do
      assert {:ok, _} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "slug" => "ma_limace",
                 "zones" => ["38185"],
                 "associated_territory_name" => "paris"
               })
    end

    test "national dataset" do
      assert {:ok, _} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "slug" => "ma_limace",
                 "national_dataset" => "true"
               })
    end

    test "territory mutual exclusion" do
      assert {:error, _} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "slug" => "ma_limace",
                 "national_dataset" => "true",
                 "insee" => "38185"
               })
    end

    test "has_real_time=true" do
      changeset =
        Dataset.changeset(%{
          "datagouv_id" => "1",
          "slug" => "ma_limace",
          "insee" => "38185",
          "resources" => [
            %{"format" => "gbfs", "url" => "coucou", "datagouv_id" => "pouet"},
            %{"format" => "gtfs", "url" => "coucou", "datagouv_id" => "pouet"}
          ]
        })

      assert {:ok, %Ecto.Changeset{changes: %{has_realtime: true}}} = changeset
    end

    test "has_real_time=false" do
      changeset =
        Dataset.changeset(%{
          "datagouv_id" => "1",
          "slug" => "ma_limace",
          "insee" => "38185",
          "resources" => [%{"format" => "gtfs", "url" => "coucou", "datagouv_id" => "pouet"}]
        })

      assert {:ok, %Ecto.Changeset{changes: %{has_realtime: false}}} = changeset
    end
  end
end
