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
  end
end
