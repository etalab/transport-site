defmodule TransportWeb.DatasetViewTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
  import TransportWeb.DatasetView

  doctest TransportWeb.DatasetView, import: true

  test "the html content of a markdown description" do
    content = "# coucou"
    dataset = %DB.Dataset{description: content}
    assert description(dataset) == {:safe, "<h1>\ncoucou</h1>\n"}
  end

  test "if the html produced is sanitized" do
    content = "<p \" onmouseout=\"alert('Gotcha!')\">coucou</p>"
    dataset = %DB.Dataset{description: content}
    assert description(dataset) == {:safe, "<p>\n  coucou</p>\n"}
  end

  test "resource to display for a low emission zone dataset" do
    dataset_two_geojson = %DB.Dataset{
      type: "low-emission-zones",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/zfe.geojson",
          format: "geojson",
          schema_name: "etalab/schema-zfe"
        },
        %DB.Resource{
          id: 2,
          url: "https://example.com/voies.geojson",
          format: "geojson",
          schema_name: "etalab/schema-zfe"
        }
      ]
    }

    dataset_title_geojson = %DB.Dataset{
      type: "low-emission-zones",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/zfe.geojson",
          format: "json",
          title: "Export de la zone en GeoJSON"
        }
      ]
    }

    dataset_only_roads = %DB.Dataset{
      type: "low-emission-zones",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/voies.geojson",
          format: "json",
          title: "Export des voies en GeoJSON"
        }
      ]
    }

    assert get_resource_to_display(dataset_two_geojson).id == 1
    assert get_resource_to_display(dataset_title_geojson).id == 1
    assert get_resource_to_display(dataset_only_roads) == nil
  end

  test "test data is up to date" do
    assert "tipi.bison-fute.gouv.fr" == Application.fetch_env!(:transport, :bison_fute_host)
  end

  test "other_official_resources is sorted by display position" do
    dataset = %DB.Dataset{
      type: "xxx",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/resource_a.geojson",
          format: "geojson",
          display_position: 1
        },
        %DB.Resource{
          id: 2,
          url: "https://example.com/resource_b.geojson",
          format: "geojson",
          display_position: 0
        }
      ]
    }

    assert [{0, 2}, {1, 1}] == dataset |> other_official_resources() |> Enum.map(&{&1.display_position, &1.id})
  end

  test "schemas_resources is sorted by display position" do
    dataset = %DB.Dataset{
      type: "low-emission-zones",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/zfe.geojson",
          format: "geojson",
          schema_name: "etalab/schema-zfe",
          display_position: 1
        },
        %DB.Resource{
          id: 2,
          url: "https://example.com/voies.geojson",
          format: "geojson",
          schema_name: "etalab/schema-zfe",
          display_position: 0
        }
      ]
    }

    assert [{0, 2}, {1, 1}] == dataset |> schemas_resources() |> Enum.map(&{&1.display_position, &1.id})
  end

  test "count_resources and count_documentation_resources" do
    dataset = insert(:dataset)
    insert(:resource, type: "documentation", url: "https://example.com/doc", dataset: dataset)
    insert(:resource, type: "main", url: "https://example.com/file", dataset: dataset)
    insert(:resource, type: "main", url: "https://example.com/community", dataset: dataset, is_community_resource: true)

    dataset = dataset |> DB.Repo.preload(:resources)

    assert count_resources(dataset) == 2
    assert count_documentation_resources(dataset) == 1
  end
end
