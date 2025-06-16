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
      type: "road-data",
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
      type: "road-data",
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
      type: "road-data",
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

  test "resource to display for BNLC" do
    dataset_two_bnlcs = %DB.Dataset{
      type: "carpooling-areas",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/bnlc.csv",
          format: "csv",
          schema_name: "etalab/schema-lieux-covoiturage",
          last_update: ~U[2016-05-24 13:26:08Z],
          type: "other"
        },
        %DB.Resource{
          id: 2,
          url: "https://example.com/bnlc-consolidated.csv",
          format: "csv",
          schema_name: "etalab/schema-lieux-covoiturage",
          last_update: ~U[2016-05-24 13:25:08Z],
          type: "other"
        }
      ]
    }

    dataset_two_bnlcs_with_the_main = %DB.Dataset{
      type: "carpooling-areas",
      resources: [
        %DB.Resource{
          id: 1,
          url: "https://example.com/bnlc.csv",
          format: "csv",
          schema_name: "etalab/schema-lieux-covoiturage",
          last_update: ~U[2016-05-24 13:26:08Z],
          type: "other"
        },
        %DB.Resource{
          id: 2,
          url: "https://example.com/bnlc-consolidated-1.csv",
          format: "csv",
          schema_name: "etalab/schema-lieux-covoiturage",
          # not the latest, but we prefer the main one
          last_update: ~U[2016-05-24 13:24:08Z],
          type: "main"
        },
        %DB.Resource{
          id: 3,
          url: "https://example.com/bnlc-consolidated-2.csv",
          format: "csv",
          schema_name: "etalab/schema-lieux-covoiturage",
          # not the latest, but we prefer the main one
          last_update: ~U[2016-05-24 13:25:08Z],
          type: "main"
        }
      ]
    }

    # Display the latest
    assert get_resource_to_display(dataset_two_bnlcs).id == 1

    # Display the latest main one
    assert get_resource_to_display(dataset_two_bnlcs_with_the_main).id == 3
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
      type: "road-data",
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
    insert(:resource, type: "documentation", url: "https://example.com/more_doc", dataset: dataset)
    insert(:resource, type: "main", url: "https://example.com/file", dataset: dataset)
    insert(:resource, type: "main", url: "https://example.com/community", dataset: dataset, is_community_resource: true)

    dataset = dataset |> DB.Repo.preload(:resources)

    assert count_resources(dataset) == 1
    assert count_documentation_resources(dataset) == 2
  end

  describe "licence_link" do
    test "inactive filter", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index))

      assert ~s{<a href="http://127.0.0.1:5100/datasets?licence=licence-ouverte">Licence Ouverte (3)</a>} ==
               conn |> licence_link(%{licence: "licence-ouverte", count: 3}) |> to_html()
    end

    test "active filter for licence-ouverte", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index, licence: "licence-ouverte"))

      assert ~s{<span class="activefilter">Licence Ouverte (3)</span>} ==
               conn |> licence_link(%{licence: "licence-ouverte", count: 3}) |> to_html()
    end

    test "filter for fr-lo and lov2 by name", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index, licence: "lov2"))

      assert ~s{<a href="http://127.0.0.1:5100/datasets?licence=licence-ouverte">Licence Ouverte (3)</a>} ==
               conn |> licence_link(%{licence: "licence-ouverte", count: 3}) |> to_html()

      conn = conn |> get(dataset_path(conn, :index, licence: "fr-lo"))

      assert ~s{<a href="http://127.0.0.1:5100/datasets?licence=licence-ouverte">Licence Ouverte (3)</a>} ==
               conn |> licence_link(%{licence: "licence-ouverte", count: 3}) |> to_html()
    end

    test "all unselected", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index))

      assert ~s{<span class="activefilter">Toutes (3)</span>} ==
               conn |> licence_link(%{licence: "all", count: 3}) |> to_html()
    end

    test "all resets filter", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index, licence: "odc-odbl", type: "public-transit"))

      assert ~s{<a href="http://127.0.0.1:5100/datasets?type=public-transit">Toutes (3)</a>} ==
               conn |> licence_link(%{licence: "all", count: 3}) |> to_html()
    end
  end

  test "order_resources_by_format does not reorder GTFS and NeTEx" do
    gtfs = insert(:resource, format: "GTFS")
    netex = insert(:resource, format: "NeTEx")
    resources = [gtfs, netex]

    assert resources == order_resources_by_format(resources)
  end

  test "icons exist" do
    Enum.each(DB.Dataset.types(), fn type ->
      path =
        __DIR__
        |> Path.join("../../../client/")
        |> Path.join(icon_type_path(type))

      assert File.exists?(path)
    end)
  end

  defp to_html(%Phoenix.LiveView.Rendered{} = rendered) do
    rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  defp to_html({:safe, _} = content), do: Phoenix.HTML.safe_to_string(content)
end
