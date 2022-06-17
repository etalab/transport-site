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

    test "territory mutual exclusion with nil INSEE code resets AOM" do
      %{datagouv_id: datagouv_id} = insert(:dataset)

      assert {:ok, %Ecto.Changeset{changes: %{aom_id: nil, region_id: 1}}} =
               Dataset.changeset(%{
                 "datagouv_id" => datagouv_id,
                 "national_dataset" => "true",
                 "insee" => nil
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

  describe "resources last content update time" do
    test "for a dataset, get resources last update times" do
      %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})

      %{id: resource_id_1} = insert(:resource, dataset_id: dataset_id)
      %{id: resource_id_2} = insert(:resource, dataset_id: dataset_id)

      # resource 1
      insert(:resource_history, %{
        resource_id: resource_id_1,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id_1,
        payload: %{download_datetime: resource_1_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      # resource 2
      insert(:resource_history, %{resource_id: resource_id_2, payload: %{}})

      dataset = DB.Dataset |> preload(:resources) |> DB.Repo.get!(dataset_id)

      assert %{resource_id_1 => resource_1_last_update_time, resource_id_2 => nil} ==
               Dataset.resources_content_updated_at(dataset)
    end

    defp insert_dataset_resource do
      dataset = insert(:dataset)
      %{id: resource_id} = insert(:resource, dataset: dataset)

      {dataset, resource_id}
    end

    test "1 resource, basic case" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      assert %{resource_id => expected_last_update_time} == Dataset.resources_content_updated_at(dataset)
    end

    test "only one resource history, we don't know the resource last content update time" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      assert Dataset.resources_content_updated_at(dataset) == %{resource_id => nil}
    end

    test "last content update time, download_datetime not in payload" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{resource_id: resource_id, payload: %{}})

      assert Dataset.resources_content_updated_at(dataset) == %{resource_id => nil}
    end

    test "last content update time, some download_datetime not in payload" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{resource_id: resource_id, payload: %{}})

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      assert Dataset.resources_content_updated_at(dataset) == %{resource_id => expected_last_update_time}
    end
  end
end
