defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory

  import Mock
  import Mox

  setup :verify_on_exit!

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "Datasets details page loads even when data.gouv is down", %{conn: conn} do
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _ -> [] end)
    # NOTE: we just want a dataset, but the factory setup is not finished, so
    # we have to provide an already built aom
    dataset = insert(:dataset, aom: insert(:aom, composition_res_id: 157))

    with_mocks [
      {Datagouvfr.Client.Reuses, [], [get: fn _dataset -> {:error, "data.gouv is down !"} end]},
      {Datagouvfr.Client.Discussions, [], [get: fn _id -> nil end]}
    ] do
      conn = conn |> get(dataset_path(conn, :details, dataset.slug))
      html = html_response(conn, 200)
      assert html =~ "réutilisations sont temporairement indisponibles"
    end
  end

  test "GET /api/datasets has HTTP cache headers set", %{conn: conn} do
    path = TransportWeb.API.Router.Helpers.dataset_path(conn, :datasets)
    conn = conn |> get(path)

    [etag] = conn |> get_resp_header("etag")
    json_response(conn, 200)
    assert etag
    assert conn |> get_resp_header("cache-control") == ["max-age=60, public, must-revalidate"]

    # Passing the previous `ETag` value in a new HTTP request returns a 304
    conn |> recycle() |> put_req_header("if-none-match", etag) |> get(path) |> response(304)
  end

  test "GET /api/datasets/:id", %{conn: conn} do
    dataset =
      %DB.Dataset{
        spatial: "title",
        type: "public-transit",
        datagouv_id: "datagouv",
        slug: "slug-1",
        resources: [
          %DB.Resource{
            url: "https://link.to/file.zip",
            latest_url: "https://static.data.gouv.fr/foo",
            content_hash: "hash",
            datagouv_id: "1",
            format: "GTFS",
            filesize: 42
          },
          %DB.Resource{
            url: "http://link.to/file.zip?foo=bar",
            datagouv_id: "2",
            metadata: %{"has_errors" => false},
            format: "geojson",
            schema_name: "etalab/schema-zfe"
          }
        ],
        aom: %DB.AOM{id: 4242, nom: "Angers Métropole", siren: "siren"}
      }
      |> DB.Repo.insert!()

    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _ -> [] end)

    path = TransportWeb.API.Router.Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)

    assert %{
             "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
             "community_resources" => [],
             "covered_area" => %{
               "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
               "name" => "Angers Métropole",
               "type" => "aom"
             },
             "created_at" => nil,
             "datagouv_id" => "datagouv",
             "history" => [],
             "id" => "datagouv",
             "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
             "publisher" => %{"name" => nil, "type" => "organization"},
             "resources" => [
               %{
                 "content_hash" => "hash",
                 "datagouv_id" => "1",
                 "features" => [],
                 "filesize" => 42,
                 "format" => "GTFS",
                 "modes" => [],
                 "original_url" => "https://link.to/file.zip",
                 "updated" => "",
                 "url" => "https://static.data.gouv.fr/foo"
               },
               %{
                 "datagouv_id" => "2",
                 "features" => [],
                 "format" => "geojson",
                 "metadata" => %{"has_errors" => false},
                 "modes" => [],
                 "original_url" => "http://link.to/file.zip?foo=bar",
                 "schema_name" => "etalab/schema-zfe",
                 "updated" => ""
               }
             ],
             "slug" => "slug-1",
             "title" => "title",
             "type" => "public-transit",
             "updated" => ""
           } == conn |> get(path) |> json_response(200)
  end

  test "the search custom message gets displayed", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index, type: "public-transit"))
    html = html_response(conn, 200)
    doc = Floki.parse_document!(html)
    [msg] = Floki.find(doc, "#custom-message")
    # extract from the category "public-transit" fr message :
    assert(Floki.text(msg) =~ "Les jeux de données référencés dans cette catégorie")
  end

  test "the search custom message is not displayed", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index, type: "inexistant"))
    html = html_response(conn, 200)
    doc = Floki.parse_document!(html)
    assert [] == Floki.find(doc, "#custom-message")
  end

  test "has_validity_period?" do
    assert TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{
             payload: %{"resource_metadata" => %{"start_date" => "2022-02-17"}}
           })

    refute TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{
             payload: %{"resource_metadata" => %{"start_date" => nil}}
           })

    refute TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{payload: %{}})
  end
end
