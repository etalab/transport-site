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

  doctest DB.Dataset, import: true

  describe "changeset of a dataset" do
    test "empty params are rejected" do
      assert {:error, _} = Dataset.changeset(%{})
    end

    test "slug is required" do
      {{:error, _}, logs} = with_log(fn -> Dataset.changeset(%{"datagouv_id" => "1"}) end)
      assert logs =~ "error while importing dataset"
    end

    test "has_real_time=true" do
      changeset =
        Dataset.changeset(%{
          "datagouv_id" => "1",
          "custom_title" => "custom title",
          "datagouv_title" => "title",
          "type" => "public-transit",
          "licence" => "lov2",
          "slug" => "ma_limace",
          "insee" => "38185",
          "resources" => [
            %{"format" => "gbfs", "url" => "coucou", "datagouv_id" => "pouet"},
            %{"format" => "gtfs", "url" => "coucou", "datagouv_id" => "pouet"}
          ],
          "organization_id" => Ecto.UUID.generate(),
          "logo" => "https://example.com/logo.png"
        })

      assert {:ok, %Ecto.Changeset{changes: %{has_realtime: true}}} = changeset
    end

    test "has_real_time=false" do
      changeset =
        Dataset.changeset(%{
          "datagouv_id" => "1",
          "custom_title" => "custom title",
          "datagouv_title" => "title",
          "type" => "public-transit",
          "licence" => "lov2",
          "organization_id" => Ecto.UUID.generate(),
          "logo" => "https://example.com/logo.png",
          "slug" => "ma_limace",
          "insee" => "38185",
          "resources" => [%{"format" => "gtfs", "url" => "coucou", "datagouv_id" => "pouet"}]
        })

      assert {:ok, %Ecto.Changeset{changes: %{has_realtime: false}}} = changeset
    end

    test "is_hidden=true" do
      assert {:ok, %Ecto.Changeset{changes: %{is_hidden: true}}} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "custom_title" => "custom title",
                 "datagouv_title" => "title",
                 "type" => "public-transit",
                 "licence" => "lov2",
                 "slug" => "ma_limace",
                 "insee" => "38185",
                 "custom_tags" => ["masqué"],
                 "organization_id" => Ecto.UUID.generate(),
                 "logo" => "https://example.com/logo.png"
               })
    end

    test "is_hidden=false" do
      assert {:ok, %Ecto.Changeset{changes: %{is_hidden: false}}} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "custom_title" => "custom title",
                 "datagouv_title" => "title",
                 "type" => "public-transit",
                 "licence" => "lov2",
                 "slug" => "ma_limace",
                 "insee" => "38185",
                 "custom_tags" => ["not_hidden"],
                 "organization_id" => Ecto.UUID.generate(),
                 "logo" => "https://example.com/logo.png"
               })
    end

    test "siren is validated" do
      {{:error, _}, logs} =
        with_log(fn ->
          Dataset.changeset(%{
            "datagouv_id" => "1",
            "datagouv_title" => "title",
            "custom_title" => "custom title",
            "slug" => "slug",
            "national_dataset" => "true",
            "legal_owner_company_siren" => "123456789"
          })
        end)

      assert logs =~ ~r/error while importing dataset(.*)legal_owner_company_siren/

      assert {:ok, %Ecto.Changeset{}} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "custom_title" => "custom title",
                 "datagouv_title" => "title",
                 "type" => "public-transit",
                 "licence" => "lov2",
                 "slug" => "slug",
                 "national_dataset" => "true",
                 "legal_owner_company_siren" => "552049447",
                 "organization_id" => Ecto.UUID.generate(),
                 "logo" => "https://example.com/logo.png"
               })
    end

    test "custom_title is trimmed" do
      assert {:ok, %Ecto.Changeset{changes: %{custom_title: "Foo"}}} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "datagouv_title" => "title",
                 "type" => "public-transit",
                 "licence" => "lov2",
                 "slug" => "slug",
                 "national_dataset" => "true",
                 "custom_title" => "  Foo ",
                 "organization_id" => Ecto.UUID.generate(),
                 "logo" => "https://example.com/logo.png"
               })
    end

    test "organization_id should be set" do
      {res, _} =
        with_log(fn ->
          DB.Dataset.changeset(%{
            "datagouv_id" => "1",
            "datagouv_title" => "title",
            "type" => "public-transit",
            "licence" => "lov2",
            "slug" => "slug",
            "national_dataset" => "true",
            "custom_title" => "Foo",
            "logo" => "https://example.com/logo.png"
          })
        end)

      assert res == {:error, ~s|%{organization_id: ["can't be blank"]}|}
    end

    test "logo should be set" do
      {res, _} =
        with_log(fn ->
          DB.Dataset.changeset(%{
            "datagouv_id" => "1",
            "datagouv_title" => "title",
            "type" => "public-transit",
            "licence" => "lov2",
            "slug" => "slug",
            "national_dataset" => "true",
            "custom_title" => "Foo",
            "organization_id" => Ecto.UUID.generate()
          })
        end)

      assert res == {:error, ~s|%{logo: ["can't be blank"]}|}
    end
  end

  describe "custom_logo_changed_at is set when updating custom_logo" do
    test "does not set custom_logo_changed_at when changing unrelated things" do
      {:ok, %Ecto.Changeset{changes: changes}} =
        Dataset.changeset(%{
          "datagouv_id" => "1",
          "datagouv_title" => "title",
          "type" => "public-transit",
          "licence" => "lov2",
          "slug" => "slug",
          "national_dataset" => "true",
          "custom_title" => "foo",
          "organization_id" => Ecto.UUID.generate(),
          "logo" => "https://example.com/logo.png"
        })

      refute Map.has_key?(changes, :custom_logo_changed_at)
    end

    test "sets custom_logo_changed_at when changing custom_logo" do
      assert {:ok, %Ecto.Changeset{changes: %{custom_logo_changed_at: custom_logo_changed_at}}} =
               Dataset.changeset(%{
                 "datagouv_id" => "1",
                 "datagouv_title" => "title",
                 "type" => "public-transit",
                 "licence" => "lov2",
                 "slug" => "slug",
                 "national_dataset" => "true",
                 "custom_title" => "foo",
                 "custom_logo" => "https://example.com/pic.jpg",
                 "organization_id" => Ecto.UUID.generate(),
                 "logo" => "https://example.com/logo.png"
               })

      assert DateTime.diff(custom_logo_changed_at, DateTime.utc_now(), :second) < 3
    end

    test "does not update fields when custom_logo is already set" do
      dataset =
        insert(:dataset, custom_logo: "https://example.com/pic.jpg", custom_logo_changed_at: DateTime.utc_now())

      {:ok, %Ecto.Changeset{changes: changes}} = Dataset.changeset(%{"datagouv_id" => dataset.datagouv_id})
      assert changes == %{population: 0}
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
        inserted_at: DateTime.utc_now() |> DateTime.add(-7200)
      })

      insert(:resource_history, %{
        resource_id: resource_id_1,
        inserted_at: resource_1_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)
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
        inserted_at: DateTime.utc_now() |> DateTime.add(-7200)
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)
      })

      assert %{resource_id => expected_last_update_time} == Dataset.resources_content_updated_at(dataset)
    end

    test "only one resource history, we don't know the resource last content update time" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-7200)
      })

      assert Dataset.resources_content_updated_at(dataset) == %{resource_id => nil}
    end

    test "last content update time, single record" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{resource_id: resource_id, payload: %{}})

      assert Dataset.resources_content_updated_at(dataset) == %{resource_id => nil}
    end

    test "last content update time, multiple datetimes" do
      {dataset, resource_id} = insert_dataset_resource()

      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-7200)
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)
      })

      assert Dataset.resources_content_updated_at(dataset) == %{resource_id => expected_last_update_time}
    end
  end

  test "formats" do
    dataset = insert(:dataset)
    insert(:resource, format: "GTFS", dataset: dataset)
    insert(:resource, format: "zip", dataset: dataset, is_community_resource: true)
    insert(:resource, format: "csv", dataset: dataset)
    insert(:resource, format: nil, dataset: dataset)

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

  describe "get_resources_related_files" do
    test "without a NeTEx resource" do
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

      insert(:resource_history,
        resource_id: r3.id,
        payload: %{"uuid" => uuid3 = Ecto.UUID.generate()},
        last_up_to_date_at: DateTime.utc_now()
      )

      insert(:data_conversion,
        resource_history_uuid: uuid1,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        payload: %{"permanent_url" => "url1", "filesize" => 21}
      )

      insert(:data_conversion,
        resource_history_uuid: uuid2,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        payload: %{"permanent_url" => "url2", "filesize" => 76}
      )

      # Should be ignored, status is `pending`
      insert(:data_conversion,
        resource_history_uuid: uuid3,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        status: :pending,
        payload: %{"permanent_url" => "url3", "filesize" => 43}
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
                 }
               },
               r2.id => %{
                 GeoJSON: %{
                   url: "url2",
                   filesize: 76,
                   resource_history_last_up_to_date_at: dt2,
                   format: "GeoJSON",
                   stable_url: "http://127.0.0.1:5100/resources/conversions/#{r2.id}/GeoJSON"
                 }
               },
               r3.id => %{GeoJSON: nil}
             } == related_resources
    end

    test "with a GTFS and NeTEx resources in the same dataset" do
      dataset = insert(:dataset)

      gtfs = insert(:resource, dataset: dataset, format: "gtfs")
      netex = insert(:resource, dataset: dataset, format: "NeTEx")

      insert(:resource_history,
        resource: gtfs,
        payload: %{"uuid" => uuid1 = Ecto.UUID.generate()},
        last_up_to_date_at: dt1 = DateTime.utc_now()
      )

      insert(:data_conversion,
        resource_history_uuid: uuid1,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        payload: %{"permanent_url" => "url1", "filesize" => 21}
      )

      dataset = dataset |> DB.Repo.preload(:resources)

      assert %{
               gtfs.id => %{
                 GeoJSON: %{
                   url: "url1",
                   filesize: 21,
                   resource_history_last_up_to_date_at: dt1,
                   format: "GeoJSON",
                   stable_url: "http://127.0.0.1:5100/resources/conversions/#{gtfs.id}/GeoJSON"
                 }
               },
               netex.id => %{GeoJSON: nil}
             } == DB.Dataset.get_resources_related_files(dataset)

      assert %{
               gtfs.id => %{
                 GeoJSON: %{
                   url: "url1",
                   filesize: 21,
                   resource_history_last_up_to_date_at: dt1,
                   format: "GeoJSON",
                   stable_url: "http://127.0.0.1:5100/resources/conversions/#{gtfs.id}/GeoJSON"
                 }
               },
               netex.id => %{GeoJSON: nil}
             } == DB.Dataset.get_resources_related_files(dataset)
    end
  end

  test "count dataset by mode" do
    france = insert(:administrative_division, type: :pays, insee: "FR", nom: "France")
    dataset = insert(:dataset)
    dataset_2 = insert(:dataset, declarative_spatial_areas: [france])

    # As filled by `Transport.CounterCache`
    insert(:resource, counter_cache: %{gtfs_modes: ["bus"]}, dataset: dataset)
    insert(:resource, counter_cache: %{gtfs_modes: ["ski"]}, dataset: dataset)

    insert(:resource, counter_cache: %{gtfs_modes: ["bus"]}, dataset: dataset_2)
    insert(:resource, counter_cache: %{gtfs_modes: ["ski"]}, dataset: dataset_2)

    assert DB.Dataset.count_by_mode("bus") == 2
    assert DB.Dataset.count_by_mode("ski") == 2
    # this counts datasets covering France with bus resources
    assert DB.Dataset.count_coach() == 1
  end

  test "count_by_custom_tag" do
    assert 0 == DB.Dataset.count_by_custom_tag("foo")
    insert(:dataset, type: "public-transit", is_active: true, custom_tags: ["bar", "foo"])
    assert 1 == DB.Dataset.count_by_custom_tag("foo")
  end

  test "correct organization type" do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    assert {:ok, %Ecto.Changeset{changes: %{organization_type: "AOM"}}} =
             Dataset.changeset(%{"datagouv_id" => datagouv_id, "organization_type" => "AOM"})
  end

  test "empty organization type" do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    # we test a random change to check if the changeset is valid without an organization type specified
    assert {:ok, %Ecto.Changeset{changes: %{licence: "fr-lo"}}} =
             Dataset.changeset(%{"datagouv_id" => datagouv_id, "licence" => "fr-lo"})
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

  test "changeset with offers" do
    %DB.Offer{id: offer_id} = offer = insert(:offer)
    dataset = insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate(), offers: [offer])
    assert [offer] == dataset.offers

    # this time we test the changeset function with the datagouv_id
    {:ok, changeset} = DB.Dataset.changeset(%{"datagouv_id" => datagouv_id, "custom_title" => "Nouveau titre"})
    DB.Repo.update!(changeset)

    dataset = DB.Dataset |> preload(:offers) |> DB.Repo.get!(dataset.id)
    assert [%DB.Offer{id: ^offer_id}] = dataset.offers
  end

  test "cannot insert a dataset with a nil organization_id" do
    message = ~r|null value in column "organization_id" of relation "dataset" violates not-null constraint|

    assert_raise Postgrex.Error, message, fn ->
      insert(:dataset, organization_id: nil)
    end
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

      {:ok, %Ecto.Changeset{} = changeset} =
        DB.Dataset.changeset(%{"datagouv_id" => dataset.datagouv_id, "organization" => pan_org})

      DB.Repo.update!(changeset)

      assert %DB.Organization{id: ^org_id} =
               dataset |> DB.Repo.reload() |> DB.Repo.preload(:organization_object) |> Map.fetch!(:organization_object)

      assert [%DB.Dataset{id: ^dataset_id}] =
               DB.Organization |> DB.Repo.one!() |> DB.Repo.preload(:datasets) |> Map.fetch!(:datasets)
    end
  end

  test "target_conversion_formats" do
    assert [:GeoJSON] ==
             DB.Dataset.target_conversion_formats(%DB.Dataset{resources: [%DB.Resource{format: "gtfs"}]})

    assert [:GeoJSON] ==
             DB.Dataset.target_conversion_formats(%DB.Dataset{
               resources: [%DB.Resource{format: "gtfs"}, %DB.Resource{format: "NeTEx"}]
             })

    assert [:GeoJSON] ==
             DB.Dataset.target_conversion_formats(%DB.Dataset{
               resources: [%DB.Resource{format: "gtfs"}, %DB.Resource{format: "NeTEx"}]
             })
  end

  test "query scopes" do
    %DB.Dataset{} = active_dataset = insert(:dataset, is_active: true)
    %DB.Dataset{} = hidden_dataset = insert(:dataset, is_active: true, is_hidden: true)
    %DB.Dataset{} = inactive_dataset = insert(:dataset, is_active: false)
    %DB.Dataset{} = archived_dataset = insert(:dataset, is_active: true, archived_at: DateTime.utc_now())

    ids = fn datasets ->
      datasets |> Enum.map(fn %DB.Dataset{id: id} -> id end) |> MapSet.new()
    end

    assert ids.([active_dataset, archived_dataset]) == DB.Dataset.base_query() |> DB.Repo.all() |> ids.()
    assert ids.([archived_dataset]) == DB.Dataset.archived() |> DB.Repo.all() |> ids.()
    assert ids.([inactive_dataset]) == DB.Dataset.inactive() |> DB.Repo.all() |> ids.()
    assert ids.([hidden_dataset]) == DB.Dataset.hidden() |> DB.Repo.all() |> ids.()

    assert ids.([active_dataset, hidden_dataset, archived_dataset]) ==
             DB.Dataset.base_with_hidden_datasets() |> DB.Repo.all() |> ids.()
  end

  test "new covered area in a dataset, create and edit" do
    departement = insert(:administrative_division)

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
               "declarative_spatial_areas" => [departement.id],
               "region_id" => 1,
               "organization_id" => Ecto.UUID.generate(),
               "tags" => [],
               "nb_reuses" => 0
             })

    {:ok, dataset} = changeset |> DB.Repo.insert_or_update()

    dataset = dataset |> DB.Repo.preload(:declarative_spatial_areas)

    [linked_departement] = dataset.declarative_spatial_areas

    assert linked_departement.id == departement.id
    assert linked_departement.nom == "Isère"

    # We’ll see if edit works too

    commune =
      insert(:administrative_division, %{type: "commune", nom: "Grenoble", insee: "38185", type_insee: "commune_38185"})

    assert {:ok, changeset} =
             DB.Dataset.changeset(%{
               "datagouv_id" => dataset.datagouv_id,
               "declarative_spatial_areas" => [commune.id, departement.id]
             })

    {:ok, changed_dataset} = changeset |> DB.Repo.insert_or_update()

    changed_dataset = changed_dataset |> DB.Repo.preload(:declarative_spatial_areas)

    # Should still be the same dataset
    assert changed_dataset.id == dataset.id

    [updated_area_1, updated_area_2] = changed_dataset.declarative_spatial_areas
    assert updated_area_1.id == departement.id
    assert updated_area_2.id == commune.id

    # Make sure we don't erase existing covered areas
    assert {:ok, changeset} =
             DB.Dataset.changeset(%{
               "datagouv_id" => dataset.datagouv_id
             })

    {:ok, changed_dataset} = changeset |> DB.Repo.update()

    changed_dataset = changed_dataset |> DB.Repo.preload(:declarative_spatial_areas)

    # Should still be the same dataset
    assert changed_dataset.id == dataset.id

    [updated_area_1, updated_area_2] = changed_dataset.declarative_spatial_areas
    assert updated_area_1.id == departement.id
    assert updated_area_2.id == commune.id
  end

  test "sets population from declarative_spatial_areas" do
    departement =
      insert(:administrative_division, type: :departement, insee: "01", type_insee: "departement_01", population: 10)

    commune = insert(:administrative_division, type: :commune, insee: "02", type_insee: "commune_02", population: 1)
    dataset = insert(:dataset, population: 0)

    assert {:ok, changeset} =
             DB.Dataset.changeset(%{
               "datagouv_id" => dataset.datagouv_id,
               "declarative_spatial_areas" => [commune.id, departement.id]
             })

    expected = commune.population + departement.population
    {:ok, %DB.Dataset{population: ^expected}} = changeset |> DB.Repo.insert_or_update()
  end
end
