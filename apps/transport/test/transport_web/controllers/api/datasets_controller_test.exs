defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias TransportWeb.API.Router.Helpers
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Datagouvfr.Client.Reuses.Mock, Datagouvfr.Client.Reuses)
    Mox.stub_with(Datagouvfr.Client.Discussions.Mock, Datagouvfr.Client.Discussions)
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    :ok
  end

  test "GET /api/datasets has HTTP cache headers set", %{conn: conn} do
    path = Helpers.dataset_path(conn, :datasets)
    conn = conn |> get(path)

    [etag] = conn |> get_resp_header("etag")
    json_response(conn, 200)
    assert etag
    assert conn |> get_resp_header("cache-control") == ["max-age=60, public, must-revalidate"]

    # Passing the previous `ETag` value in a new HTTP request returns a 304
    conn |> recycle() |> put_req_header("if-none-match", etag) |> get(path) |> response(304)
  end

  test "GET /api/datasets *with* history, multi_validation and resource_metadata", %{conn: conn} do
    dataset =
      insert(:dataset,
        custom_title: "title",
        type: "public-transit",
        licence: "lov2",
        datagouv_id: "datagouv",
        slug: "slug-1",
        is_active: true,
        aom: insert(:aom, nom: "Angers Métropole", siren: "siren")
      )

    resource =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/file.zip",
        latest_url: "https://static.data.gouv.fr/foo",
        content_hash: "hash",
        datagouv_id: "1",
        type: "main",
        format: "GTFS",
        filesize: 42
      )

    _gbfs_resource =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/gbfs.json",
        datagouv_id: "2",
        type: "main",
        format: "gbfs"
      )

    insert(:resource_metadata,
      multi_validation:
        insert(:multi_validation,
          resource_history: insert(:resource_history, resource_id: resource.id),
          validator: Transport.Validators.GTFSTransport.validator_name()
        ),
      modes: ["bus"],
      features: ["couleurs des lignes"],
      metadata: %{"foo" => "bar"}
    )

    path = Helpers.dataset_path(conn, :datasets)

    assert [
             %{
               "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
               "community_resources" => [],
               "covered_area" => %{
                 "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
                 "name" => "Angers Métropole",
                 "type" => "aom"
               },
               "created_at" => nil,
               "datagouv_id" => "datagouv",
               "id" => "datagouv",
               "licence" => "lov2",
               "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
               "publisher" => %{"name" => nil, "type" => "organization"},
               "resources" => [
                 %{
                   "content_hash" => "hash",
                   "datagouv_id" => "1",
                   "features" => ["couleurs des lignes"],
                   "filesize" => 42,
                   "format" => "GTFS",
                   "metadata" => %{"foo" => "bar"},
                   "modes" => ["bus"],
                   "original_url" => "https://link.to/file.zip",
                   "title" => "GTFS.zip",
                   "type" => "main",
                   "updated" => "",
                   "url" => "https://static.data.gouv.fr/foo"
                 },
                 %{
                   "datagouv_id" => "2",
                   "format" => "gbfs",
                   "original_url" => "https://link.to/gbfs.json",
                   "title" => "GTFS.zip",
                   "type" => "main",
                   "updated" => "",
                   "url" => "url"
                 }
               ],
               "slug" => "slug-1",
               "title" => "title",
               "type" => "public-transit",
               "updated" => ""
             }
           ] == conn |> get(path) |> json_response(200)
  end

  test "GET /api/datasets *without* history, multi_validation and resource_metadata", %{conn: conn} do
    insert(:resource,
      dataset:
        insert(:dataset,
          custom_title: "title",
          type: "public-transit",
          licence: "lov2",
          datagouv_id: "datagouv",
          slug: "slug-1",
          is_active: true,
          aom: insert(:aom, nom: "Angers Métropole", siren: "siren")
        ),
      url: "https://link.to/gbfs.json",
      datagouv_id: "2",
      type: "main",
      format: "gbfs"
    )

    path = Helpers.dataset_path(conn, :datasets)

    assert [
             %{
               "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
               "community_resources" => [],
               "covered_area" => %{
                 "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
                 "name" => "Angers Métropole",
                 "type" => "aom"
               },
               "created_at" => nil,
               "datagouv_id" => "datagouv",
               "id" => "datagouv",
               "licence" => "lov2",
               "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
               "publisher" => %{"name" => nil, "type" => "organization"},
               "resources" => [
                 %{
                   "datagouv_id" => "2",
                   "format" => "gbfs",
                   "original_url" => "https://link.to/gbfs.json",
                   "title" => "GTFS.zip",
                   "type" => "main",
                   "updated" => "",
                   "url" => "url"
                 }
               ],
               "slug" => "slug-1",
               "title" => "title",
               "type" => "public-transit",
               "updated" => ""
             }
           ] == conn |> get(path) |> json_response(200)
  end

  test "GET /api/datasets/:id *without* history, multi_validation and resource_metadata", %{conn: conn} do
    dataset =
      %DB.Dataset{
        custom_title: "title",
        is_active: true,
        type: "public-transit",
        licence: "lov2",
        datagouv_id: "datagouv",
        slug: "slug-1",
        resources: [
          %DB.Resource{
            url: "https://link.to/file.zip",
            latest_url: "https://static.data.gouv.fr/foo",
            content_hash: "hash",
            datagouv_id: "1",
            type: "main",
            format: "GTFS",
            filesize: 42
          },
          %DB.Resource{
            url: "http://link.to/file.zip?foo=bar",
            datagouv_id: "2",
            type: "main",
            format: "geojson",
            schema_name: "etalab/schema-zfe"
          }
        ],
        aom: %DB.AOM{id: 4242, nom: "Angers Métropole", siren: "siren"}
      }
      |> DB.Repo.insert!()

    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)

    path = Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)

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
                 "filesize" => 42,
                 "type" => "main",
                 "format" => "GTFS",
                 "original_url" => "https://link.to/file.zip",
                 "updated" => "",
                 "url" => "https://static.data.gouv.fr/foo"
               },
               %{
                 "datagouv_id" => "2",
                 "type" => "main",
                 "format" => "geojson",
                 "original_url" => "http://link.to/file.zip?foo=bar",
                 "schema_name" => "etalab/schema-zfe",
                 "updated" => ""
               }
             ],
             "slug" => "slug-1",
             "title" => "title",
             "type" => "public-transit",
             "licence" => "lov2",
             "updated" => ""
           } == conn |> get(path) |> json_response(200)
  end

  test "GET /api/datasets/:id *with* history, multi_validation and resource_metadata", %{conn: conn} do
    dataset =
      insert(:dataset,
        custom_title: "title",
        type: "public-transit",
        licence: "lov2",
        datagouv_id: "datagouv",
        slug: "slug-1",
        is_active: true,
        aom: insert(:aom, nom: "Angers Métropole", siren: "siren")
      )

    resource =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/file.zip",
        latest_url: "https://static.data.gouv.fr/foo",
        content_hash: "hash",
        datagouv_id: "1",
        type: "main",
        format: "GTFS",
        filesize: 42
      )

    _gbfs_resource =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/gbfs.json",
        datagouv_id: "2",
        type: "main",
        format: "gbfs"
      )

    insert(:resource_metadata,
      multi_validation:
        insert(:multi_validation,
          resource_history: insert(:resource_history, resource_id: resource.id),
          validator: Transport.Validators.GTFSTransport.validator_name()
        ),
      modes: ["bus"],
      features: ["couleurs des lignes"],
      metadata: %{"foo" => "bar"}
    )

    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)

    path = Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)

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
             "licence" => "lov2",
             "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
             "publisher" => %{"name" => nil, "type" => "organization"},
             "resources" => [
               %{
                 "content_hash" => "hash",
                 "datagouv_id" => "1",
                 "features" => ["couleurs des lignes"],
                 "filesize" => 42,
                 "format" => "GTFS",
                 "metadata" => %{"foo" => "bar"},
                 "modes" => ["bus"],
                 "original_url" => "https://link.to/file.zip",
                 "title" => "GTFS.zip",
                 "type" => "main",
                 "updated" => "",
                 "url" => "https://static.data.gouv.fr/foo"
               },
               %{
                 "datagouv_id" => "2",
                 "format" => "gbfs",
                 "original_url" => "https://link.to/gbfs.json",
                 "title" => "GTFS.zip",
                 "type" => "main",
                 "updated" => "",
                 "url" => "url"
               }
             ],
             "slug" => "slug-1",
             "title" => "title",
             "type" => "public-transit",
             "updated" => ""
           } == conn |> get(path) |> json_response(200)
  end
end
