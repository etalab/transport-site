defmodule Transport.DatasetIndexTest do
  use ExUnit.Case, async: false
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "build_index" do
    test "indexes active datasets with their facets" do
      dataset =
        insert(:dataset,
          type: "public-transit",
          licence: "fr-lo",
          has_realtime: true,
          is_active: true,
          is_hidden: false
        )

      insert(:resource, dataset: dataset, format: "GTFS")
      insert(:resource, dataset: dataset, format: "NeTEx")

      index = Transport.DatasetIndex.build_index()

      assert Map.has_key?(index, dataset.id)

      entry = Map.fetch!(index, dataset.id)
      assert entry.type == "public-transit"
      assert entry.licence == "fr-lo"
      assert entry.has_realtime == true
      assert entry.formats == ["GTFS", "NeTEx"]
    end

    test "excludes inactive datasets" do
      insert(:dataset, is_active: false)

      index = Transport.DatasetIndex.build_index()
      assert index == %{}
    end

    test "excludes hidden datasets" do
      insert(:dataset, is_active: true, is_hidden: true)

      index = Transport.DatasetIndex.build_index()
      assert index == %{}
    end

    test "excludes community resources from formats" do
      dataset = insert(:dataset)
      insert(:resource, dataset: dataset, format: "GTFS")
      insert(:resource, dataset: dataset, format: "csv", is_community_resource: true)

      index = Transport.DatasetIndex.build_index()

      assert Map.fetch!(index, dataset.id).formats == ["GTFS"]
    end

    test "indexes custom_tags and organization_id" do
      %DB.Organization{id: org_id} = insert(:organization)

      dataset =
        insert(:dataset,
          custom_tags: ["foo", "bar"],
          organization_id: org_id
        )

      index = Transport.DatasetIndex.build_index()
      entry = Map.fetch!(index, dataset.id)

      assert entry.custom_tags == ["foo", "bar"]
      assert entry.organization_id == org_id
    end

    test "indexes population, custom_title, inserted_at, datagouv_title" do
      dataset = insert(:dataset, population: 42, custom_title: "My Title", datagouv_title: "DG Title")

      index = Transport.DatasetIndex.build_index()
      entry = Map.fetch!(index, dataset.id)

      assert entry.population == 42
      assert entry.custom_title == "My Title"
      assert entry.datagouv_title == "DG Title"
      assert entry.inserted_at == dataset.inserted_at
    end

    test "indexes modes from resource counter_cache" do
      dataset = insert(:dataset)
      insert(:resource, dataset: dataset, counter_cache: %{gtfs_modes: ["bus", "tramway"]})
      insert(:resource, dataset: dataset, counter_cache: %{gtfs_modes: ["bus", "ferry"]})

      index = Transport.DatasetIndex.build_index()
      entry = Map.fetch!(index, dataset.id)

      assert Enum.sort(entry.modes) == ["bus", "ferry", "tramway"]
    end

    test "indexes offer identifiers" do
      offer1 = insert(:offer)
      offer2 = insert(:offer)
      dataset = insert(:dataset, offers: [offer1, offer2])

      index = Transport.DatasetIndex.build_index()
      entry = Map.fetch!(index, dataset.id)

      assert Enum.sort(entry.offer_ids) == Enum.sort([offer1.identifiant_offre, offer2.identifiant_offre])
    end

    test "excludes archived datasets" do
      insert(:dataset, is_active: true, archived_at: DateTime.utc_now())

      index = Transport.DatasetIndex.build_index()
      assert index == %{}
    end

    test "indexes dataset subtypes" do
      ds_urban = insert(:dataset_subtype, parent_type: "public-transit", slug: "urban")
      ds_intercity = insert(:dataset_subtype, parent_type: "public-transit", slug: "intercity")

      dataset =
        insert(:dataset,
          type: "public-transit",
          is_active: true,
          is_hidden: false,
          dataset_subtypes: [ds_urban, ds_intercity]
        )

      index = Transport.DatasetIndex.build_index()

      entry = Map.fetch!(index, dataset.id)
      assert Enum.sort(entry.subtypes) == ["intercity", "urban"]
    end
  end

  describe "facet computation" do
    test "types" do
      d1 = insert(:dataset, type: "public-transit")
      d2 = insert(:dataset, type: "public-transit")
      d3 = insert(:dataset, type: "road-data")

      index = Transport.DatasetIndex.build_index()
      result = Transport.DatasetIndex.types(index, [d1.id, d2.id, d3.id])

      assert Enum.sort_by(result, & &1.type) == [
               %{type: "public-transit", count: 2, msg: "Transport public collectif"},
               %{type: "road-data", count: 1, msg: "Données routières"}
             ]
    end

    test "licences groups fr-lo and lov2 into licence-ouverte" do
      d1 = insert(:dataset, licence: "fr-lo")
      d2 = insert(:dataset, licence: "lov2")
      d3 = insert(:dataset, licence: "mobility-licence")

      index = Transport.DatasetIndex.build_index()
      result = Transport.DatasetIndex.licences(index, [d1.id, d2.id, d3.id])

      assert result == [
               %{licence: "licence-ouverte", count: 2},
               %{licence: "mobility-licence", count: 1}
             ]
    end

    test "realtime_count" do
      d1 = insert(:dataset, has_realtime: true)
      d2 = insert(:dataset, has_realtime: false)
      d3 = insert(:dataset, has_realtime: true)

      index = Transport.DatasetIndex.build_index()
      result = Transport.DatasetIndex.realtime_count(index, [d1.id, d2.id, d3.id])

      assert result == %{all: 3, true: 2}
    end

    test "resource_format_count" do
      d1 = insert(:dataset)
      insert(:resource, dataset: d1, format: "GTFS")
      insert(:resource, dataset: d1, format: "NeTEx")
      d2 = insert(:dataset)
      insert(:resource, dataset: d2, format: "GTFS")

      index = Transport.DatasetIndex.build_index()
      result = Transport.DatasetIndex.resource_format_count(index, [d1.id, d2.id])

      assert Enum.find(result, fn {k, _} -> k == :all end) == {:all, 2}
      assert Enum.find(result, fn {k, _} -> k == "GTFS" end) == {"GTFS", 2}
      assert Enum.find(result, fn {k, _} -> k == "NeTEx" end) == {"NeTEx", 1}
    end

    test "facets only count requested dataset IDs" do
      d1 = insert(:dataset, type: "public-transit")
      _d2 = insert(:dataset, type: "road-data")

      index = Transport.DatasetIndex.build_index()
      result = Transport.DatasetIndex.types(index, [d1.id])

      assert result == [%{type: "public-transit", count: 1, msg: "Transport public collectif"}]
    end

    test "filter_dataset_ids by type" do
      d1 = insert(:dataset, type: "public-transit")
      _d2 = insert(:dataset, type: "road-data")

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"type" => "public-transit"})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids by subtype" do
      ds_urban = insert(:dataset_subtype, parent_type: "public-transit", slug: "urban")
      d1 = insert(:dataset, type: "public-transit", dataset_subtypes: [ds_urban])
      _d2 = insert(:dataset, type: "public-transit", dataset_subtypes: [])

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"subtype" => "urban"})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids by licence (licence-ouverte groups fr-lo and lov2)" do
      d1 = insert(:dataset, licence: "fr-lo")
      d2 = insert(:dataset, licence: "lov2")
      _d3 = insert(:dataset, licence: "odc-odbl")

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"licence" => "licence-ouverte"})
      assert Enum.sort(ids) == Enum.sort([d1.id, d2.id])
    end

    test "filter_dataset_ids by has_realtime" do
      d1 = insert(:dataset, has_realtime: true)
      _d2 = insert(:dataset, has_realtime: false)

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"filter" => "has_realtime"})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids by format" do
      d1 = insert(:dataset)
      insert(:resource, dataset: d1, format: "GTFS")
      d2 = insert(:dataset)
      insert(:resource, dataset: d2, format: "gbfs")

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"format" => "GTFS"})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids by custom_tag" do
      d1 = insert(:dataset, custom_tags: ["foo", "bar"])
      _d2 = insert(:dataset, custom_tags: ["baz"])

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"custom_tag" => "foo"})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids by organization_id" do
      %DB.Organization{id: org_id} = insert(:organization)
      d1 = insert(:dataset, organization_id: org_id)
      _d2 = insert(:dataset)

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"organization_id" => to_string(org_id)})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids with combined filters" do
      d1 = insert(:dataset, type: "public-transit", licence: "fr-lo", has_realtime: true)
      _d2 = insert(:dataset, type: "public-transit", licence: "fr-lo", has_realtime: false)
      _d3 = insert(:dataset, type: "road-data", licence: "fr-lo", has_realtime: true)

      index = Transport.DatasetIndex.build_index()

      ids =
        Transport.DatasetIndex.filter_dataset_ids(index, %{
          "type" => "public-transit",
          "licence" => "licence-ouverte",
          "filter" => "has_realtime"
        })

      assert ids == [d1.id]
    end

    test "filter_dataset_ids by modes" do
      d1 = insert(:dataset)
      insert(:resource, dataset: d1, counter_cache: %{gtfs_modes: ["bus", "tramway"]})
      d2 = insert(:dataset)
      insert(:resource, dataset: d2, counter_cache: %{gtfs_modes: ["bus"]})
      _d3 = insert(:dataset)

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"modes" => ["bus"]})
      assert Enum.sort(ids) == Enum.sort([d1.id, d2.id])

      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{"modes" => ["tramway"]})
      assert ids == [d1.id]
    end

    test "filter_dataset_ids by identifiant_offre" do
      offer = insert(:offer)
      d1 = insert(:dataset, offers: [offer])
      _d2 = insert(:dataset)

      index = Transport.DatasetIndex.build_index()

      ids =
        Transport.DatasetIndex.filter_dataset_ids(index, %{"identifiant_offre" => to_string(offer.identifiant_offre)})

      assert ids == [d1.id]
    end

    test "filter_dataset_ids with no filters returns all" do
      d1 = insert(:dataset)
      d2 = insert(:dataset)

      index = Transport.DatasetIndex.build_index()
      ids = Transport.DatasetIndex.filter_dataset_ids(index, %{})
      assert Enum.sort(ids) == Enum.sort([d1.id, d2.id])
    end

    test "subtypes counts correctly filtered by parent_type" do
      ds_urban = insert(:dataset_subtype, parent_type: "public-transit", slug: "urban")
      ds_intercity = insert(:dataset_subtype, parent_type: "public-transit", slug: "intercity")
      ds_bicycle = insert(:dataset_subtype, parent_type: "vehicles-sharing", slug: "bicycle")

      d1 = insert(:dataset, type: "public-transit", dataset_subtypes: [ds_urban])
      d2 = insert(:dataset, type: "public-transit", dataset_subtypes: [ds_urban, ds_intercity])
      d3 = insert(:dataset, type: "vehicles-sharing", dataset_subtypes: [ds_bicycle])

      index = Transport.DatasetIndex.build_index()

      # d2 has both urban and intercity: all count should be 2 (distinct datasets), not 3
      pt_result = Transport.DatasetIndex.subtypes(index, [d1.id, d2.id, d3.id], "public-transit")

      assert pt_result.all == 2

      assert Enum.sort_by(pt_result.subtypes, & &1.subtype) == [
               %{subtype: "intercity", count: 1, msg: DB.Dataset.subtype_to_str("intercity")},
               %{subtype: "urban", count: 2, msg: DB.Dataset.subtype_to_str("urban")}
             ]

      vs_result = Transport.DatasetIndex.subtypes(index, [d1.id, d2.id, d3.id], "vehicles-sharing")

      assert vs_result == %{
               all: 1,
               subtypes: [%{subtype: "bicycle", count: 1, msg: DB.Dataset.subtype_to_str("bicycle")}]
             }
    end
  end

  describe "order_dataset_ids" do
    test "order_by alpha sorts by custom_title ASC" do
      d1 = insert(:dataset, custom_title: "B dataset")
      d2 = insert(:dataset, custom_title: "A dataset")

      index = Transport.DatasetIndex.build_index()
      ids = [d1.id, d2.id]
      sorted = Transport.DatasetIndex.order_dataset_ids(ids, index, %{"order_by" => "alpha"})
      assert sorted == [d2.id, d1.id]
    end

    test "order_by most_recent sorts by inserted_at DESC with nulls last" do
      today = DateTime.utc_now()
      last_week = DateTime.add(today, -7, :day)

      d1 = insert(:dataset, inserted_at: last_week)
      d2 = insert(:dataset, inserted_at: today)
      d3 = insert(:dataset) |> Ecto.Changeset.change(%{inserted_at: nil}) |> DB.Repo.update!()

      index = Transport.DatasetIndex.build_index()
      ids = [d1.id, d2.id, d3.id]
      sorted = Transport.DatasetIndex.order_dataset_ids(ids, index, %{"order_by" => "most_recent"})
      assert sorted == [d2.id, d1.id, d3.id]
    end

    test "default order sorts by population DESC then custom_title ASC" do
      d1 = insert(:dataset, population: 10, custom_title: "AAA")
      d2 = insert(:dataset, population: 20, custom_title: "BBB")
      d3 = insert(:dataset, population: 20, custom_title: "ABC")

      index = Transport.DatasetIndex.build_index()
      ids = [d1.id, d2.id, d3.id]
      sorted = Transport.DatasetIndex.order_dataset_ids(ids, index, %{})
      assert sorted == [d3.id, d2.id, d1.id]
    end

    test "default order prioritizes base nationale datasets" do
      pan_publisher = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)

      d1 = insert(:dataset, population: 100, custom_title: "Z dataset")

      d2 =
        insert(:dataset,
          population: 1,
          custom_title: "Base nationale des GTFS",
          organization_id: pan_publisher
        )

      index = Transport.DatasetIndex.build_index()
      ids = [d1.id, d2.id]
      sorted = Transport.DatasetIndex.order_dataset_ids(ids, index, %{})
      assert sorted == [d2.id, d1.id]
    end

    test "with q param returns ids unchanged (no in-memory sort)" do
      d1 = insert(:dataset, custom_title: "B")
      d2 = insert(:dataset, custom_title: "A")

      index = Transport.DatasetIndex.build_index()
      ids = [d1.id, d2.id]
      sorted = Transport.DatasetIndex.order_dataset_ids(ids, index, %{"q" => "some search"})
      assert sorted == ids
    end
  end
end
