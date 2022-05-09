defmodule TransportWeb.DatasetViewTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
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

  test "download url", %{conn: conn} do
    # Files hosted on data.gouv.fr
    assert download_url(conn, %DB.Resource{
             filetype: "file",
             url: "https://demo-static.data.gouv.fr/resources/base-nationale-zfe/20220412-121638/voies.geojson",
             latest_url: latest_url = "https://demo.data.gouv.fr/fake_stable_url"
           }) == latest_url

    assert download_url(conn, %DB.Resource{
             filetype: "file",
             url: "https://static.data.gouv.fr/resources/base-nationale-zfe/20220412-121638/voies.geojson",
             latest_url: latest_url = "https://data.gouv.fr/fake_stable_url"
           }) == latest_url

    # Bison Futé files
    assert download_url(conn, %DB.Resource{
             filetype: "remote",
             url: "http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/QTV-DIR/refDir.csv",
             latest_url: latest_url = "https://data.gouv.fr/fake_stable_url"
           }) == latest_url

    # File not hosted on data.gouv.fr
    assert download_url(conn, %DB.Resource{filetype: "file", url: url = "https://data.example.com/voies.geojson"}) ==
             url

    # Remote filetype / can direct download
    assert download_url(conn, %DB.Resource{filetype: "remote", url: url = "https://data.example.com/data"}) == url
    # http URL
    assert download_url(conn, %DB.Resource{id: id = 1, filetype: "remote", url: "http://data.example.com/data"}) ==
             resource_path(conn, :download, id)

    # file hosted on GitHub
    assert download_url(conn, %DB.Resource{
             id: id = 1,
             filetype: "remote",
             url:
               "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/898dc67fb19fae2464c24a85a0557e8ccce18791/bnlc-.csv"
           }) == resource_path(conn, :download, id)
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
