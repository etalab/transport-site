defmodule TransportWeb.API.DatasetControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias TransportWeb.API.Router.Helpers
  import DB.Factory
  import Mox

  setup :verify_on_exit!

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
        datagouv_id: datagouv_id = "datagouv",
        slug: "slug-1",
        is_active: true,
        created_at: ~U[2021-12-23 13:30:40.000000Z],
        aom: insert(:aom, nom: "Angers Métropole", siren: "siren")
      )

    resource_1 =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/file.zip",
        latest_url: "https://static.data.gouv.fr/foo",
        datagouv_id: "1",
        type: "main",
        format: "GTFS",
        filesize: 42
      )

    resource_2 =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/file2.zip",
        latest_url: "https://static.data.gouv.fr/foo2",
        datagouv_id: "2",
        type: "main",
        format: "GTFS",
        filesize: 43
      )

    gbfs_resource =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/gbfs.json",
        latest_url: "https://link.to/latest",
        datagouv_id: "3",
        title: "GBFS",
        type: "main",
        format: "gbfs",
        is_available: false
      )

    insert(:resource_metadata,
      multi_validation:
        insert(:multi_validation,
          resource_history: insert(:resource_history, resource_id: resource_1.id),
          validator: Transport.Validators.GTFSTransport.validator_name()
        ),
      modes: ["bus"],
      features: ["couleurs des lignes"],
      metadata: %{"foo" => "bar"}
    )

    insert(:resource_metadata,
      multi_validation:
        insert(:multi_validation,
          resource_history: insert(:resource_history, resource_id: resource_2.id),
          validator: Transport.Validators.GTFSTransport.validator_name()
        ),
      modes: ["skate"],
      features: ["clim"],
      metadata: %{"foo" => "bar2"}
    )

    path = Helpers.dataset_path(conn, :datasets)

    dataset_res = %{
      "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
      "community_resources" => [],
      "covered_area" => %{
        "aom" => %{"name" => "Angers Métropole", "siren" => "siren"},
        "name" => "Angers Métropole",
        "type" => "aom"
      },
      "created_at" => "2021-12-23",
      "datagouv_id" => "datagouv",
      "id" => "datagouv",
      "licence" => "lov2",
      "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
      "publisher" => %{"name" => nil, "type" => "organization"},
      "resources" => [
        %{
          "page_url" => resource_page_url(resource_1),
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
          "url" => "https://static.data.gouv.fr/foo",
          "is_available" => true
        },
        %{
          "page_url" => resource_page_url(resource_2),
          "datagouv_id" => "2",
          "features" => ["clim"],
          "filesize" => 43,
          "format" => "GTFS",
          "metadata" => %{"foo" => "bar2"},
          "modes" => ["skate"],
          "original_url" => "https://link.to/file2.zip",
          "title" => "GTFS.zip",
          "type" => "main",
          "updated" => "",
          "url" => "https://static.data.gouv.fr/foo2",
          "is_available" => true
        },
        %{
          "page_url" => resource_page_url(gbfs_resource),
          "datagouv_id" => gbfs_resource.datagouv_id,
          "format" => gbfs_resource.format,
          "original_url" => gbfs_resource.url,
          "title" => gbfs_resource.title,
          "type" => "main",
          "updated" => "",
          "url" => gbfs_resource.latest_url,
          "is_available" => gbfs_resource.is_available
        }
      ],
      "slug" => "slug-1",
      "title" => "title",
      "type" => "public-transit",
      "updated" => ""
    }

    assert [dataset_res] == conn |> get(path) |> json_response(200)

    # check the result is in line with a query on this dataset
    # only difference: individual dataset call has the resource history
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)
    dataset_res = dataset_res |> Map.put("history", [])
    assert dataset_res == conn |> get(Helpers.dataset_path(conn, :by_id, datagouv_id)) |> json_response(200)
  end

  test "GET /api/datasets *without* history, multi_validation and resource_metadata", %{conn: conn} do
    resource =
      insert(:resource,
        dataset:
          insert(:dataset,
            custom_title: "title",
            type: "public-transit",
            licence: "lov2",
            datagouv_id: "datagouv",
            slug: "slug-1",
            is_active: true,
            created_at: ~U[2021-12-23 13:30:40.000000Z],
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
               "created_at" => "2021-12-23",
               "datagouv_id" => "datagouv",
               "id" => "datagouv",
               "licence" => "lov2",
               "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
               "publisher" => %{"name" => nil, "type" => "organization"},
               "resources" => [
                 %{
                   "page_url" => resource_page_url(resource),
                   "is_available" => true,
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
        created_at: ~U[2021-12-23 13:30:40.000000Z],
        aom: %DB.AOM{id: 4242, nom: "Angers Métropole", siren: "siren"}
      }
      |> DB.Repo.insert!()
      |> DB.Repo.preload(:resources)

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
             "created_at" => "2021-12-23",
             "datagouv_id" => "datagouv",
             "history" => [],
             "id" => "datagouv",
             "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
             "publisher" => %{"name" => nil, "type" => "organization"},
             "resources" => [
               %{
                 "is_available" => true,
                 "page_url" => dataset.resources |> Enum.find(&(&1.format == "GTFS")) |> resource_page_url(),
                 "datagouv_id" => "1",
                 "filesize" => 42,
                 "type" => "main",
                 "format" => "GTFS",
                 "original_url" => "https://link.to/file.zip",
                 "updated" => "",
                 "url" => "https://static.data.gouv.fr/foo"
               },
               %{
                 "is_available" => true,
                 "page_url" => dataset.resources |> Enum.find(&(&1.format == "geojson")) |> resource_page_url(),
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
        created_at: ~U[2021-12-23 13:30:40.000000Z],
        aom: insert(:aom, nom: "Angers Métropole", siren: "siren")
      )

    resource =
      insert(:resource,
        dataset_id: dataset.id,
        url: "https://link.to/file.zip",
        latest_url: "https://static.data.gouv.fr/foo",
        datagouv_id: "1",
        type: "main",
        format: "GTFS",
        filesize: 42
      )

    gbfs_resource =
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
             "created_at" => "2021-12-23",
             "datagouv_id" => "datagouv",
             "history" => [],
             "id" => "datagouv",
             "licence" => "lov2",
             "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
             "publisher" => %{"name" => nil, "type" => "organization"},
             "resources" => [
               %{
                 "page_url" => resource_page_url(resource),
                 "is_available" => true,
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
                 "page_url" => resource_page_url(gbfs_resource),
                 "is_available" => true,
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

  test "gtfs-rt features are filled", %{conn: conn} do
    dataset_1 = insert(:dataset, datagouv_id: datagouv_id_1 = Ecto.UUID.generate())
    resource_1 = insert(:resource, dataset_id: dataset_1.id, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_1.id, features: ["a"])
    insert(:resource_metadata, resource_id: resource_1.id, features: ["a", "b"])
    insert(:resource_metadata, resource_id: resource_1.id, features: ["c"])

    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)

    # call to specific dataset
    path = Helpers.dataset_path(conn, :by_id, datagouv_id_1)
    %{"resources" => [%{"features" => features}]} = conn |> get(path) |> json_response(200)
    assert features |> Enum.sort() == ["a", "b", "c"]

    # add another dataset
    dataset_2 = insert(:dataset, datagouv_id: datagouv_id_2 = Ecto.UUID.generate())
    resource_2 = insert(:resource, dataset_id: dataset_2.id, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_2.id, features: ["x"])

    # call for all datasets
    path = Helpers.dataset_path(conn, :datasets)
    datasets = conn |> get(path) |> json_response(200)

    assert ["a", "b", "c"] ==
             datasets
             |> Enum.find(fn d -> Map.get(d, "datagouv_id") == datagouv_id_1 end)
             |> Map.get("resources")
             |> Enum.at(0)
             |> Map.get("features")
             |> Enum.sort()

    assert ["x"] ==
             datasets
             |> Enum.find(fn d -> Map.get(d, "datagouv_id") == datagouv_id_2 end)
             |> Map.get("resources")
             |> Enum.at(0)
             |> Map.get("features")
             |> Enum.sort()
  end

  defp resource_page_url(%DB.Resource{id: id}) do
    TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id)
  end
end
