defmodule TransportWeb.DatasetViewTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import TransportWeb.DatasetView

  doctest TransportWeb.DatasetView

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
end
