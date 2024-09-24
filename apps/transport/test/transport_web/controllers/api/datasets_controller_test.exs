defmodule TransportWeb.API.DatasetControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias TransportWeb.API.Router.Helpers
  import DB.Factory
  import Mox
  import OpenApiSpex.TestAssertions

  setup :verify_on_exit!

  test "GET /api/datasets has HTTP cache headers set", %{conn: conn} do
    path = Helpers.dataset_path(conn, :datasets)
    conn = conn |> get(path)

    [etag] = conn |> get_resp_header("etag")
    json = json_response(conn, 200)
    assert etag
    assert conn |> get_resp_header("cache-control") == ["max-age=60, public, must-revalidate"]

    # Passing the previous `ETag` value in a new HTTP request returns a 304
    conn |> recycle() |> put_req_header("if-none-match", etag) |> get(path) |> response(304)

    api_spec = TransportWeb.API.Spec.spec()
    assert_schema(json, "DatasetsResponse", api_spec)
  end

  test "GET /api/datasets does not include inactive or hidden datasets", %{conn: conn} do
    insert(:dataset, is_active: false)
    insert(:dataset, is_active: true, is_hidden: true)

    assert [] == conn |> get(Helpers.dataset_path(conn, :datasets)) |> json_response(200)
  end

  test "GET /api/datasets then /api/datasets/:id *with* history, multi_validation and resource_metadata",
       %{conn: conn} do
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
          "updated" => resource_1.last_update |> DateTime.to_iso8601(),
          "page_url" => resource_page_url(resource_1),
          "id" => resource_1.id,
          "datagouv_id" => "1",
          "features" => ["couleurs des lignes"],
          "filesize" => 42,
          "format" => "GTFS",
          "metadata" => %{"foo" => "bar"},
          "modes" => ["bus"],
          "original_url" => "https://link.to/file.zip",
          "title" => "GTFS.zip",
          "type" => "main",
          "url" => "https://static.data.gouv.fr/foo",
          "is_available" => true
        },
        %{
          "updated" => resource_2.last_update |> DateTime.to_iso8601(),
          "page_url" => resource_page_url(resource_2),
          "id" => resource_2.id,
          "datagouv_id" => "2",
          "features" => ["clim"],
          "filesize" => 43,
          "format" => "GTFS",
          "metadata" => %{"foo" => "bar2"},
          "modes" => ["skate"],
          "original_url" => "https://link.to/file2.zip",
          "title" => "GTFS.zip",
          "type" => "main",
          "url" => "https://static.data.gouv.fr/foo2",
          "is_available" => true
        },
        %{
          "updated" => gbfs_resource.last_update |> DateTime.to_iso8601(),
          "page_url" => resource_page_url(gbfs_resource),
          "id" => gbfs_resource.id,
          "datagouv_id" => gbfs_resource.datagouv_id,
          "format" => gbfs_resource.format,
          "original_url" => gbfs_resource.url,
          "title" => gbfs_resource.title,
          "type" => "main",
          "url" => gbfs_resource.latest_url,
          "is_available" => gbfs_resource.is_available
        }
      ],
      "slug" => "slug-1",
      "title" => "title",
      "type" => "public-transit",
      "updated" =>
        [resource_1, gbfs_resource, resource_2]
        |> Enum.map(& &1.last_update)
        |> Enum.max(DateTime)
        |> DateTime.to_iso8601()
    }

    assert json = conn |> get(path) |> json_response(200)
    assert [dataset_res] == json
    assert_schema(json, "DatasetsResponse", TransportWeb.API.Spec.spec())

    # check the result is in line with a query on this dataset
    # only difference: individual dataset adds information about history and conversions
    setup_empty_history_resources()

    dataset_res =
      dataset_res
      |> Map.merge(%{"history" => []})
      |> Map.put("resources", Enum.map(dataset_res["resources"], &Map.put(&1, "conversions", %{})))

    json = conn |> get(Helpers.dataset_path(conn, :by_id, datagouv_id)) |> json_response(200)
    assert dataset_res == json
    assert_schema(json, "DatasetDetails", TransportWeb.API.Spec.spec())
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

    json = conn |> get(path) |> json_response(200)

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
                   "id" => resource.id,
                   "is_available" => true,
                   "datagouv_id" => "2",
                   "format" => "gbfs",
                   "original_url" => "https://link.to/gbfs.json",
                   "title" => "GTFS.zip",
                   "type" => "main",
                   "updated" => resource.last_update |> DateTime.to_iso8601(),
                   "url" => "url"
                 }
               ],
               "slug" => "slug-1",
               "title" => "title",
               "type" => "public-transit",
               "updated" => resource.last_update |> DateTime.to_iso8601()
             }
           ] == json

    assert_schema(json, "DatasetsResponse", TransportWeb.API.Spec.spec())
  end

  test "GET /api/datasets/:id *without* history, multi_validation and resource_metadata", %{conn: conn} do
    dataset =
      insert(:dataset,
        custom_title: "title",
        is_active: true,
        type: "public-transit",
        licence: "lov2",
        datagouv_id: "datagouv",
        slug: "slug-1",
        resources: [
          %DB.Resource{
            last_import: DateTime.utc_now(),
            last_update: last_update_gtfs = DateTime.utc_now() |> DateTime.add(-2, :hour),
            url: "https://link.to/file.zip",
            latest_url: "https://static.data.gouv.fr/foo",
            datagouv_id: "1",
            type: "main",
            format: "GTFS",
            filesize: 42,
            title: "The title"
          },
          %DB.Resource{
            last_import: DateTime.utc_now(),
            last_update: last_update_geojson = DateTime.utc_now() |> DateTime.add(-1, :hour),
            url: "http://link.to/file.zip?foo=bar",
            latest_url: "http://static.data.gouv.fr/?foo=bar",
            datagouv_id: "2",
            type: "main",
            format: "geojson",
            schema_name: "etalab/schema-zfe",
            title: "The other title"
          }
        ],
        created_at: ~U[2021-12-23 13:30:40.000000Z],
        last_update: DateTime.utc_now(),
        aom: %DB.AOM{id: 4242, nom: "Angers Métropole", siren: "siren"}
      )

    setup_empty_history_resources()

    path = Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)

    json = conn |> get(path) |> json_response(200)

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
                 "id" => Enum.find(dataset.resources, &(&1.format == "GTFS")).id,
                 "page_url" => dataset.resources |> Enum.find(&(&1.format == "GTFS")) |> resource_page_url(),
                 "datagouv_id" => "1",
                 "filesize" => 42,
                 "type" => "main",
                 "format" => "GTFS",
                 "original_url" => "https://link.to/file.zip",
                 "updated" => last_update_gtfs |> DateTime.to_iso8601(),
                 "url" => "https://static.data.gouv.fr/foo",
                 "conversions" => %{},
                 "title" => "The title"
               },
               %{
                 "is_available" => true,
                 "id" => Enum.find(dataset.resources, &(&1.format == "geojson")).id,
                 "page_url" => dataset.resources |> Enum.find(&(&1.format == "geojson")) |> resource_page_url(),
                 "datagouv_id" => "2",
                 "type" => "main",
                 "format" => "geojson",
                 "original_url" => "http://link.to/file.zip?foo=bar",
                 "schema_name" => "etalab/schema-zfe",
                 "updated" => last_update_geojson |> DateTime.to_iso8601(),
                 "url" => "http://static.data.gouv.fr/?foo=bar",
                 "conversions" => %{},
                 "title" => "The other title"
               }
             ],
             "slug" => "slug-1",
             "title" => "title",
             "type" => "public-transit",
             "licence" => "lov2",
             "updated" => [last_update_gtfs, last_update_geojson] |> Enum.max(DateTime) |> DateTime.to_iso8601()
           } == json

    assert_schema(json, "DatasetDetails", TransportWeb.API.Spec.spec())
  end

  test "GET /api/datasets/:id *with* history, conversions, multi_validation and resource_metadata", %{conn: conn} do
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

    resource_history =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{"uuid" => uuid1 = Ecto.UUID.generate()},
        last_up_to_date_at: last_up_to_date_at = DateTime.utc_now()
      )

    insert(:resource_metadata,
      multi_validation:
        insert(:multi_validation,
          resource_history: resource_history,
          validator: Transport.Validators.GTFSTransport.validator_name()
        ),
      modes: ["bus"],
      features: ["couleurs des lignes"],
      metadata: %{"foo" => "bar"}
    )

    insert(:data_conversion,
      resource_history_uuid: uuid1,
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      converter: DB.DataConversion.converter_to_use("GeoJSON"),
      payload: %{"permanent_url" => "https://example.com/url1", "filesize" => filesize = 43}
    )

    setup_empty_history_resources()

    path = Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)

    json = conn |> get(path) |> json_response(200)

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
                 "updated" => resource.last_update |> DateTime.to_iso8601(),
                 "page_url" => resource_page_url(resource),
                 "id" => resource.id,
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
                 "url" => "https://static.data.gouv.fr/foo",
                 "conversions" => %{
                   "GeoJSON" => %{
                     "filesize" => filesize,
                     "last_check_conversion_is_up_to_date" => last_up_to_date_at |> DateTime.to_iso8601(),
                     "stable_url" => "http://127.0.0.1:5100/resources/conversions/#{resource.id}/GeoJSON"
                   }
                 }
               },
               %{
                 "updated" => gbfs_resource.last_update |> DateTime.to_iso8601(),
                 "page_url" => resource_page_url(gbfs_resource),
                 "id" => gbfs_resource.id,
                 "is_available" => true,
                 "datagouv_id" => "2",
                 "format" => "gbfs",
                 "original_url" => "https://link.to/gbfs.json",
                 "title" => "GTFS.zip",
                 "type" => "main",
                 "url" => "url",
                 "conversions" => %{}
               }
             ],
             "slug" => "slug-1",
             "title" => "title",
             "type" => "public-transit",
             "updated" =>
               [resource, gbfs_resource] |> Enum.map(& &1.last_update) |> Enum.max(DateTime) |> DateTime.to_iso8601()
           } == json

    assert_schema(json, "DatasetDetails", TransportWeb.API.Spec.spec())
  end

  test "GET /api/datasets/:id with an hidden dataset", %{conn: conn} do
    %DB.Dataset{datagouv_id: datagouv_id} = insert(:dataset, is_active: true, is_hidden: true)

    setup_empty_history_resources()

    assert %{"datagouv_id" => ^datagouv_id} =
             conn
             |> get(Helpers.dataset_path(conn, :by_id, datagouv_id))
             |> json_response(200)
  end

  test "gtfs-rt features are filled", %{conn: conn} do
    dataset_1 = insert(:dataset, datagouv_id: datagouv_id_1 = Ecto.UUID.generate())
    resource_1 = insert(:resource, dataset_id: dataset_1.id, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_1.id, features: ["a"])
    insert(:resource_metadata, resource_id: resource_1.id, features: ["a", "b"])
    insert(:resource_metadata, resource_id: resource_1.id, features: ["c"])

    setup_empty_history_resources()

    # call to specific dataset
    path = Helpers.dataset_path(conn, :by_id, datagouv_id_1)
    dataset_response = conn |> get(path) |> json_response(200)
    %{"resources" => [%{"features" => features}]} = dataset_response

    assert_schema(dataset_response, "DatasetDetails", TransportWeb.API.Spec.spec())

    assert features |> Enum.sort() == ["a", "b", "c"]

    # add another dataset
    dataset_2 = insert(:dataset, datagouv_id: datagouv_id_2 = Ecto.UUID.generate())
    resource_2 = insert(:resource, dataset_id: dataset_2.id, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_2.id, features: ["x"])

    # call for all datasets
    path = Helpers.dataset_path(conn, :datasets)
    datasets = conn |> get(path) |> json_response(200)
    assert_schema(datasets, "DatasetsResponse", TransportWeb.API.Spec.spec())

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

  defp setup_empty_history_resources do
    expect(Transport.History.Fetcher.Mock, :history_resources, fn %DB.Dataset{}, options ->
      assert Keyword.equal?(options, preload_validations: false, max_records: 25, fetch_mode: :all)
      []
    end)
  end

  defp resource_page_url(%DB.Resource{id: id}) do
    TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id)
  end
end
