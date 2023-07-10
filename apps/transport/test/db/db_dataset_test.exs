defmodule DB.DatasetDBTest do
  @moduledoc """
  Tests on the Dataset schema
  """
  use DB.DatabaseCase, cleanup: [:datasets]
  use Oban.Testing, repo: DB.Repo
  alias DB.Repo
  import DB.Factory
  import ExUnit.CaptureLog
  import Ecto.Query

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
      {{:error, _}, logs} = with_log(fn -> Dataset.changeset(%{"datagouv_id" => "1"}) end)
      assert logs =~ "error while importing dataset"
    end

    test "some geographic link is required" do
      {{:error, _}, logs} = with_log(fn -> Dataset.changeset(%{"datagouv_id" => "1", "slug" => "ma_limace"}) end)
      assert logs =~ "error while importing dataset"
    end

    test "with insee code of a commune linked to an aom, it works" do
      assert {:ok, _} = Dataset.changeset(%{"datagouv_id" => "1", "slug" => "ma_limace", "insee" => "38185"})
    end

    test "with datagouv_zone only, it fails" do
      {{:error, _}, logs} =
        with_log(fn ->
          Dataset.changeset(%{
            "datagouv_id" => "1",
            "slug" => "ma_limace",
            "zones" => ["38185"]
          })
        end)

      assert logs =~ "error while importing dataset"
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
      {{:error, _}, logs} =
        with_log(fn ->
          Dataset.changeset(%{
            "datagouv_id" => "1",
            "slug" => "ma_limace",
            "national_dataset" => "true",
            "insee" => "38185"
          })
        end)

      assert logs =~ "error while importing dataset"
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

  describe "mobility-licence" do
    test "does not change the licence if the magic custom tag is not set" do
      insert(:dataset, licence: "lov2", datagouv_id: datagouv_id = Ecto.UUID.generate(), custom_tags: nil)

      assert {:ok, %Ecto.Changeset{changes: %{licence: "fr-lo"}}} =
               Dataset.changeset(%{"datagouv_id" => datagouv_id, "licence" => "fr-lo"})
    end

    test "if the magic tag is set, change the licence" do
      insert(:dataset, custom_tags: ["licence-mobilités"], datagouv_id: datagouv_id = Ecto.UUID.generate())

      assert {:ok, %Ecto.Changeset{changes: %{licence: "mobility-licence"}}} =
               Dataset.changeset(%{"datagouv_id" => datagouv_id})

      assert {:ok, %Ecto.Changeset{changes: %{licence: "mobility-licence"}}} =
               Dataset.changeset(%{"datagouv_id" => datagouv_id, "licence" => "fr-lo"})
    end

    test "ignores other tags in custom_tags" do
      insert(:dataset, custom_tags: ["foo"], datagouv_id: datagouv_id = Ecto.UUID.generate())

      assert {:ok, %Ecto.Changeset{changes: %{licence: "fr-lo"}}} =
               Dataset.changeset(%{"datagouv_id" => datagouv_id, "licence" => "fr-lo"})
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

  test "get_other_datasets" do
    aom = insert(:aom)
    dataset = insert(:dataset, aom: aom, is_active: true)

    assert Dataset.get_other_datasets(dataset) == []

    _inactive_dataset = insert(:dataset, aom: aom, is_active: false)

    assert Dataset.get_other_datasets(dataset) == []

    other_dataset = insert(:dataset, aom: aom, is_active: true)

    assert dataset |> Dataset.get_other_datasets() |> Enum.map(& &1.id) == [other_dataset.id]
  end

  test "formats" do
    dataset = insert(:dataset)
    insert(:resource, format: "GTFS", dataset: dataset)
    insert(:resource, format: "zip", dataset: dataset, is_community_resource: true)
    insert(:resource, format: "csv", dataset: dataset)

    assert ["GTFS", "csv"] == dataset |> DB.Repo.preload(:resources) |> Dataset.formats()
  end

  test "validate" do
    dataset = insert(:dataset)
    %{id: gtfs_resource_id} = insert(:resource, format: "GTFS", dataset: dataset)
    %{id: gbfs_resource_id} = insert(:resource, format: "gbfs", dataset: dataset)
    # Ignored because it's a community resource
    insert(:resource, format: "GTFS", dataset: dataset, is_community_resource: true)

    Dataset.validate(dataset)

    assert [
             %Oban.Job{
               args: %{"resource_id" => ^gbfs_resource_id},
               worker: "Transport.Jobs.ResourceValidationJob",
               conflict?: false
             },
             %Oban.Job{
               args: %{
                 "first_job_args" => %{"resource_id" => ^gtfs_resource_id},
                 "jobs" => [
                   ["Elixir.Transport.Jobs.ResourceHistoryJob", %{}, %{}],
                   ["Elixir.Transport.Jobs.ResourceHistoryValidationJob", %{"force_validation" => false}, %{}]
                 ]
               },
               worker: "Transport.Jobs.Workflow",
               conflict?: false
             }
           ] = all_enqueued()

    # Executing again does not create a conflict, even if the job has `unique` params
    Dataset.validate(dataset)

    assert [
             %Oban.Job{
               args: %{"resource_id" => ^gbfs_resource_id},
               worker: "Transport.Jobs.ResourceValidationJob",
               conflict?: false
             },
             %Oban.Job{
               args: %{
                 "first_job_args" => %{"resource_id" => gtfs_resource_id},
                 "jobs" => [
                   ["Elixir.Transport.Jobs.ResourceHistoryJob", %{}, %{}],
                   ["Elixir.Transport.Jobs.ResourceHistoryValidationJob", %{"force_validation" => false}, %{}]
                 ]
               },
               worker: "Transport.Jobs.Workflow",
               conflict?: false
             },
             %Oban.Job{
               args: %{"resource_id" => ^gbfs_resource_id},
               worker: "Transport.Jobs.ResourceValidationJob",
               conflict?: false
             },
             %Oban.Job{
               args: %{
                 "first_job_args" => %{"resource_id" => gtfs_resource_id},
                 "jobs" => [
                   ["Elixir.Transport.Jobs.ResourceHistoryJob", %{}, %{}],
                   ["Elixir.Transport.Jobs.ResourceHistoryValidationJob", %{"force_validation" => false}, %{}]
                 ]
               },
               worker: "Transport.Jobs.Workflow",
               conflict?: false
             }
           ] = all_enqueued()
  end

  test "get resources related files (GeoJSON, NeTEx,...)" do
    %{id: dataset_id} = insert(:dataset)

    r1 = insert(:resource, dataset_id: dataset_id)
    r2 = insert(:resource, dataset_id: dataset_id)
    r3 = insert(:resource, dataset_id: dataset_id)

    insert(:resource_history,
      resource_id: r1.id,
      payload: %{"uuid" => uuid1 = Ecto.UUID.generate()},
      last_up_to_date_at: dt1 = DateTime.utc_now()
    )

    insert(:resource_history,
      resource_id: r2.id,
      payload: %{"uuid" => uuid2 = Ecto.UUID.generate()},
      last_up_to_date_at: dt2 = DateTime.utc_now()
    )

    insert(:data_conversion,
      resource_history_uuid: uuid1,
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      payload: %{"permanent_url" => "url1", "filesize" => 21}
    )

    insert(:data_conversion,
      resource_history_uuid: uuid1,
      convert_from: "GTFS",
      convert_to: "NeTEx",
      payload: %{"permanent_url" => "url11", "filesize" => 42}
    )

    insert(:data_conversion,
      resource_history_uuid: uuid2,
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      payload: %{"permanent_url" => "url2", "filesize" => 76}
    )

    dataset = DB.Dataset |> preload(:resources) |> DB.Repo.get(dataset_id)

    related_resources = DB.Dataset.get_resources_related_files(dataset)

    assert %{
             r1.id => %{
               GeoJSON: %{
                 url: "url1",
                 filesize: 21,
                 resource_history_last_up_to_date_at: dt1,
                 format: "GeoJSON",
                 stable_url: "http://127.0.0.1:5100/resources/conversions/#{r1.id}/GeoJSON"
               },
               NeTEx: %{
                 url: "url11",
                 filesize: 42,
                 resource_history_last_up_to_date_at: dt1,
                 format: "NeTEx",
                 stable_url: "http://127.0.0.1:5100/resources/conversions/#{r1.id}/NeTEx"
               }
             },
             r2.id => %{
               GeoJSON: %{
                 url: "url2",
                 filesize: 76,
                 resource_history_last_up_to_date_at: dt2,
                 format: "GeoJSON",
                 stable_url: "http://127.0.0.1:5100/resources/conversions/#{r2.id}/GeoJSON"
               },
               NeTEx: nil
             },
             r3.id => %{GeoJSON: nil, NeTEx: nil}
           } == related_resources
  end

  test "count dataset by mode" do
    insert(:region, id: 14, nom: "France")
    region = insert(:region)

    %{dataset: dataset} = insert_resource_and_friends(Date.utc_today(), region_id: region.id, modes: ["bus"])
    insert_resource_and_friends(Date.utc_today(), dataset: dataset, modes: ["ski"])

    %{dataset: dataset_2} = insert_resource_and_friends(Date.utc_today(), region_id: 14, modes: ["bus"])
    insert_resource_and_friends(Date.utc_today(), dataset: dataset_2, modes: ["ski"])

    insert_resource_and_friends(Date.utc_today(), region_id: 14)

    assert DB.Dataset.count_by_mode("bus") == 2
    assert DB.Dataset.count_by_mode("ski") == 2
    # this counts national datasets (region id = 14) with bus resources
    assert DB.Dataset.count_coach() == 1
  end

  test "correct organization type" do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    assert {:ok, %Ecto.Changeset{changes: %{organization_type: "AOM"}}} =
             Dataset.changeset(%{"datagouv_id" => datagouv_id, "organization_type" => "AOM"})
  end

  test "empty organization type" do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    # we test a random change to check if the changeset is valid without an organization type specified
    assert {:ok, %Ecto.Changeset{changes: %{licence: "lov2"}}} =
             Dataset.changeset(%{"datagouv_id" => datagouv_id, "licence" => "lov2"})
  end

  test "incorrect organization type" do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    {res, logs} =
      with_log(fn ->
        Dataset.changeset(%{"datagouv_id" => datagouv_id, "organization_type" => "US Gvt"})
      end)

    assert logs =~ "Le type d'organisation (publicateur) est invalide"
    assert {:error, "%{organization_type: [\"Le type d'organisation (publicateur) est invalide\"]}"} == res
  end

  test "dataset last resource history" do
    dataset = insert(:dataset)

    r1 = insert(:resource, dataset_id: dataset.id)
    insert(:resource_history, resource_id: r1.id, inserted_at: DateTime.utc_now() |> DateTime.add(-3, :day))
    rh = insert(:resource_history, resource_id: r1.id, inserted_at: DateTime.utc_now())

    r2 = insert(:resource, dataset_id: dataset.id)

    insert(:resource)

    last_resource_history = DB.Dataset.last_resource_history(dataset.id)

    assert length(last_resource_history) == 2
    assert last_resource_history |> Enum.find(&(&1.id == r1.id)) |> Map.get(:resource_history) == [rh]
    assert last_resource_history |> Enum.find(&(&1.id == r2.id)) |> Map.get(:resource_history) == []
  end

  test "changeset with aom legal owners" do
    %{id: aom_id} = aom = insert(:aom)
    dataset = insert(:dataset, legal_owners_aom: [aom])
    assert [aom] == dataset.legal_owners_aom

    # this function should not erase the associated legal owners
    {:ok, changeset} = DB.Dataset.changeset(%{"dataset_id" => dataset.id, "custom_title" => "Nouveau titre"})
    DB.Repo.update!(changeset)

    dataset = DB.Dataset |> preload(:legal_owners_aom) |> DB.Repo.get!(dataset.id)
    assert [%DB.AOM{id: ^aom_id}] = dataset.legal_owners_aom
  end

  test "changeset with region legal owners" do
    %{id: region_id} = region = insert(:region)
    dataset = insert(:dataset, datagouv_id: datagouv_id = "some_datagouv_id", legal_owners_region: [region])
    assert [region] == dataset.legal_owners_region

    # this time we test the changeset function with the datagouv_id
    {:ok, changeset} = DB.Dataset.changeset(%{"datagouv_id" => datagouv_id, "custom_title" => "Nouveau titre"})
    DB.Repo.update!(changeset)

    dataset = DB.Dataset |> preload(:legal_owners_region) |> DB.Repo.get!(dataset.id)
    assert [%DB.Region{id: ^region_id}] = dataset.legal_owners_region
  end

  test "changeset to national dataset" do
    %{id: region_id} = insert(:region)
    insert(:dataset, region_id: region_id, datagouv_id: datagouv_id = "1234", aom: nil)

    {:ok, changeset} =
      DB.Dataset.changeset(%{"datagouv_id" => datagouv_id, "national_dataset" => "true", "region_id" => ""})

    %{region_id: national_region_id} = DB.Repo.update!(changeset)
    assert national_region_id != region_id
  end

  describe "organization" do
    test "sets an existing org" do
      pan_org = %{
        acronym: nil,
        badges: [],
        id: org_id = Ecto.UUID.generate(),
        logo: "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
        logo_thumbnail: "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
        name: "PAN",
        slug: "equipe-transport-data-gouv-fr"
      }

      insert(:organization, pan_org)
      dataset = insert(:dataset)

      {:ok, %Ecto.Changeset{} = changeset} =
        DB.Dataset.changeset(%{
          "datagouv_id" => dataset.datagouv_id,
          "organization" => pan_org |> Map.new(fn {k, v} -> {to_string(k), v} end)
        })

      DB.Repo.update!(changeset)

      assert %DB.Organization{id: ^org_id} =
               dataset |> DB.Repo.reload() |> DB.Repo.preload(:organization_object) |> Map.fetch!(:organization_object)
    end

    test "creates and sets an org" do
      pan_org = %{
        "acronym" => nil,
        "badges" => [],
        "id" => org_id = Ecto.UUID.generate(),
        "logo" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
        "logo_thumbnail" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
        "name" => "PAN",
        "slug" => "equipe-transport-data-gouv-fr"
      }

      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
      {:ok, %Ecto.Changeset{} = changeset} = DB.Dataset.changeset(%{"datagouv_id" => dataset.datagouv_id, "organization" => pan_org})

      DB.Repo.update!(changeset)

      assert %DB.Organization{id: ^org_id} =
               dataset |> DB.Repo.reload() |> DB.Repo.preload(:organization_object) |> Map.fetch!(:organization_object)
      assert [%DB.Dataset{id: ^dataset_id}] = DB.Organization |> DB.Repo.one!() |> DB.Repo.preload(:datasets) |> Map.fetch!(:datasets)
    end
  end
end
