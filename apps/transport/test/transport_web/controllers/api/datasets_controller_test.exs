defmodule TransportWeb.API.DatasetControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias TransportWeb.API.Router.Helpers
  import DB.Factory
  import Mox
  import OpenApiSpex.TestAssertions

  @pan_org_id "5abca8d588ee386ee6ece479"

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

  describe "token_auth" do
    test "GET /api/datasets with an invalid token", %{conn: conn} do
      assert conn
             |> put_req_header("authorization", "invalid")
             |> get(Helpers.dataset_path(conn, :datasets))
             |> json_response(401) == %{"error" => "You must set a valid Authorization header"}

      assert [] == DB.APIRequest |> DB.Repo.all()
    end

    test "GET /api/datasets with a valid token", %{conn: conn} do
      %DB.Token{id: token_id} = token = insert_token()

      assert conn
             |> put_req_header("authorization", token.secret)
             |> get(Helpers.dataset_path(conn, :datasets))
             |> json_response(200)

      assert [
               %DB.APIRequest{
                 method: "TransportWeb.API.DatasetController#datasets",
                 path: "/api/datasets",
                 token_id: ^token_id
               }
             ] = DB.APIRequest |> DB.Repo.all()
    end

    test "GET /api/datasets without a token", %{conn: conn} do
      assert conn
             |> get(Helpers.dataset_path(conn, :datasets))
             |> json_response(200)

      assert [
               %DB.APIRequest{
                 method: "TransportWeb.API.DatasetController#datasets",
                 path: "/api/datasets",
                 token_id: nil
               }
             ] = DB.APIRequest |> DB.Repo.all()
    end

    test "GET /api/datasets/:id with an invalid token", %{conn: conn} do
      assert conn
             |> put_req_header("authorization", "invalid")
             |> get(Helpers.dataset_path(conn, :by_id, Ecto.UUID.generate()))
             |> json_response(401) == %{"error" => "You must set a valid Authorization header"}

      assert [] == DB.APIRequest |> DB.Repo.all()
    end

    test "GET /api/datasets/:id with a valid token", %{conn: conn} do
      %DB.Token{id: token_id} = token = insert_token()
      dataset = insert(:dataset)

      setup_empty_history_resources()

      assert conn
             |> put_req_header("authorization", token.secret)
             |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id))
             |> json_response(200)

      path = "/api/datasets/#{dataset.datagouv_id}"

      assert [
               %DB.APIRequest{method: "TransportWeb.API.DatasetController#by_id", path: ^path, token_id: ^token_id}
             ] = DB.APIRequest |> DB.Repo.all()
    end

    test "GET /api/datasets/:id without a token", %{conn: conn} do
      dataset = insert(:dataset)

      setup_empty_history_resources()

      assert conn
             |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id))
             |> json_response(200)

      path = "/api/datasets/#{dataset.datagouv_id}"

      assert [
               %DB.APIRequest{
                 method: "TransportWeb.API.DatasetController#by_id",
                 path: ^path,
                 token_id: nil
               }
             ] = DB.APIRequest |> DB.Repo.all()
    end
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
        organization: "org",
        organization_id: "org_id",
        declarative_spatial_areas: [
          build(:administrative_division, nom: "Angers Métropole", insee: "123456", type: :epci)
        ],
        custom_tags: ["foo", "bar"],
        offers: [
          insert(:offer,
            identifiant_offre: 1,
            nom_commercial: "Superbus",
            nom_aom: "Super AOM",
            type_transport: "Transport urbain"
          )
        ]
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
      "community_resources" => [],
      "covered_area" => [%{"insee" => "123456", "nom" => "Angers Métropole", "type" => "epci"}],
      "legal_owners" => [],
      "created_at" => "2021-12-23",
      "datagouv_id" => "datagouv",
      "id" => "datagouv",
      "licence" => "lov2",
      "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
      "publisher" => %{"name" => "org", "type" => "organization", "id" => "org_id"},
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
        |> DateTime.to_iso8601(),
      "tags" => ["foo", "bar"],
      "offers" => [
        %{
          "identifiant_offre" => 1,
          "nom_aom" => "Super AOM",
          "nom_commercial" => "Superbus",
          "type_transport" => "Transport urbain"
        }
      ]
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
            organization: "org",
            organization_id: "org_id",
            declarative_spatial_areas: [
              build(:administrative_division, nom: "Angers Métropole", insee: "123456", type: :epci)
            ]
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
               "community_resources" => [],
               "covered_area" => [%{"insee" => "123456", "nom" => "Angers Métropole", "type" => "epci"}],
               "legal_owners" => [],
               "created_at" => "2021-12-23",
               "datagouv_id" => "datagouv",
               "id" => "datagouv",
               "licence" => "lov2",
               "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
               "publisher" => %{"name" => "org", "id" => "org_id", "type" => "organization"},
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
               "updated" => resource.last_update |> DateTime.to_iso8601(),
               "tags" => [],
               "offers" => []
             }
           ] == json

    assert_schema(json, "DatasetsResponse", TransportWeb.API.Spec.spec())
  end

  test "GET /api/datasets without the experimental tagged datasets", %{conn: conn} do
    insert(:resource,
      dataset:
        insert(:dataset,
          custom_title: "TC",
          type: "public-transit",
          licence: "lov2",
          datagouv_id: "datagouv-1",
          slug: "slug-1",
          is_active: true,
          created_at: ~U[2021-12-23 13:30:40.000000Z],
          tags: ["netex"]
        ),
      url: "https://link.to/gbfs.json",
      datagouv_id: "1",
      type: "main",
      format: "gbfs"
    )

    insert(:resource,
      dataset:
        insert(:dataset,
          custom_title: "Tarifs (expérimental)",
          type: "public-transit",
          licence: "lov2",
          datagouv_id: "datagouv-2",
          slug: "slug-2",
          is_active: true,
          created_at: ~U[2021-12-23 13:30:40.000000Z],
          custom_tags: ["netex", "experimental"]
        ),
      url: "https://link.to/gbfs.json",
      datagouv_id: "2",
      type: "main",
      format: "gbfs"
    )

    path = Helpers.dataset_path(conn, :datasets)

    json = conn |> get(path) |> json_response(200)

    assert [%{"title" => "TC"}] = json
  end

  test "GET /api/datasets/:id *without* history, multi_validation and resource_metadata", %{conn: conn} do
    aom = insert(:aom, nom: "Angers Métropole", siren: "siren", id: 4242)
    region = DB.Region |> Ecto.Query.where(insee: "52") |> DB.Repo.one!()

    dataset =
      insert(:dataset,
        custom_title: "title",
        is_active: true,
        type: "public-transit",
        licence: "lov2",
        datagouv_id: "datagouv",
        slug: "slug-1",
        organization: "org",
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
        legal_owners_aom: [aom],
        legal_owners_region: [region],
        declarative_spatial_areas: [
          build(:administrative_division, nom: "Angers Métropole", insee: "123456", type: :epci)
        ]
      )

    setup_empty_history_resources()

    path = Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)

    json = conn |> get(path) |> json_response(200)

    assert %{
             "community_resources" => [],
             "covered_area" => [%{"insee" => "123456", "nom" => "Angers Métropole", "type" => "epci"}],
             "legal_owners" => [
               %{"name" => "Angers Métropole", "siren" => "siren", "type" => "aom"},
               %{"insee" => "52", "name" => "Pays de la Loire", "type" => "region"}
             ],
             "created_at" => "2021-12-23",
             "datagouv_id" => "datagouv",
             "history" => [],
             "id" => "datagouv",
             "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
             "publisher" => %{"name" => "org", "id" => dataset.organization_id, "type" => "organization"},
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
             "updated" => [last_update_gtfs, last_update_geojson] |> Enum.max(DateTime) |> DateTime.to_iso8601(),
             "tags" => [],
             "offers" => []
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
        organization: "org",
        organization_id: "org_id",
        declarative_spatial_areas: [
          build(:administrative_division, nom: "Angers Métropole", insee: "123456", type: :epci)
        ]
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
             "community_resources" => [],
             "covered_area" => [%{"insee" => "123456", "nom" => "Angers Métropole", "type" => "epci"}],
             "legal_owners" => [],
             "created_at" => "2021-12-23",
             "datagouv_id" => "datagouv",
             "history" => [],
             "id" => "datagouv",
             "licence" => "lov2",
             "page_url" => "http://127.0.0.1:5100/datasets/slug-1",
             "publisher" => %{"name" => "org", "id" => "org_id", "type" => "organization"},
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
               [resource, gbfs_resource] |> Enum.map(& &1.last_update) |> Enum.max(DateTime) |> DateTime.to_iso8601(),
             "tags" => [],
             "offers" => []
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

  test "GET /api/datasets/:id with a dataset tagged 'experimental'", %{conn: conn} do
    setup_empty_history_resources()

    %DB.Dataset{datagouv_id: visible_dataset_datagouv_id} =
      insert(:dataset,
        datagouv_id: "datagouv-1",
        is_active: true,
        created_at: ~U[2021-12-23 13:30:40.000000Z],
        tags: ["netex"]
      )

    %DB.Dataset{datagouv_id: experimental_dataset_datagouv_id} =
      insert(:dataset,
        datagouv_id: "datagouv-2",
        is_active: true,
        created_at: ~U[2021-12-23 13:30:40.000000Z],
        custom_tags: ["netex", "experimental"]
      )

    assert %{"datagouv_id" => ^visible_dataset_datagouv_id} =
             conn
             |> get(Helpers.dataset_path(conn, :by_id, visible_dataset_datagouv_id))
             |> json_response(200)

    conn
    |> get(Helpers.dataset_path(conn, :by_id, experimental_dataset_datagouv_id))
    |> json_response(404)
  end

  test "gtfs-rt features are filled", %{conn: conn} do
    dataset_1 =
      insert(:dataset,
        datagouv_id: datagouv_id_1 = Ecto.UUID.generate(),
        organization: "org",
        organization_id: "org_id"
      )

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
    dataset_2 =
      insert(:dataset,
        datagouv_id: datagouv_id_2 = Ecto.UUID.generate(),
        organization: "org2",
        organization_id: "org2_id"
      )

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

  test "GET /api/datasets/:id with a PAN resource", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    setup_empty_history_resources()

    json = conn |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)) |> json_response(200)

    download_url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource.id)
    assert [%{"url" => ^download_url}] = json["resources"]
  end

  test "GET /api/datasets/:id with a PAN resource and a token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    %DB.Token{secret: secret} = insert_token()

    setup_empty_history_resources()

    json =
      conn
      |> put_req_header("authorization", secret)
      |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id))
      |> json_response(200)

    download_url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource.id)
    auth_url = download_url <> "?token=#{secret}"
    assert [%{"url" => ^auth_url}] = json["resources"]
  end

  test "GET /api/datasets/:id with a dataset with experimentation tag", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)
    setup_empty_history_resources()

    json = conn |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)) |> json_response(200)

    download_url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource.id)
    assert [%{"url" => ^download_url}] = json["resources"]
  end

  test "GET /api/datasets/:id with a dataset with experimentation tag and a token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)
    %DB.Token{secret: secret} = insert_token()

    setup_empty_history_resources()

    json =
      conn
      |> put_req_header("authorization", secret)
      |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id))
      |> json_response(200)

    download_url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource.id)
    auth_url = download_url <> "?token=#{secret}"
    assert [%{"url" => ^auth_url}] = json["resources"]
  end

  test "GET /api/datasets with a PAN dataset and a token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    %DB.Token{secret: secret} = insert_token()

    json =
      conn
      |> put_req_header("authorization", secret)
      |> get(Helpers.dataset_path(conn, :datasets))
      |> json_response(200)

    download_url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource.id)
    auth_url = download_url <> "?token=#{secret}"
    assert [%{"url" => ^auth_url}] = json |> hd() |> Map.get("resources")
  end

  test "GET /api/datasets with a dataset with experimentation tag and a token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)
    %DB.Token{secret: secret} = insert_token()

    json =
      conn
      |> put_req_header("authorization", secret)
      |> get(Helpers.dataset_path(conn, :datasets))
      |> json_response(200)

    download_url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource.id)
    auth_url = download_url <> "?token=#{secret}"
    assert [%{"url" => ^auth_url}] = json |> hd() |> Map.get("resources")
  end

  test "GET /api/datasets with a dataset with experimentation tag and a real-time resource", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, latest_url: "https://example.com/gbfs", format: "gbfs", dataset: dataset)

    assert DB.Resource.real_time?(resource)

    json =
      conn
      |> get(Helpers.dataset_path(conn, :datasets))
      |> json_response(200)

    download_url = resource.latest_url
    assert [%{"url" => ^download_url}] = json |> hd() |> Map.get("resources")
  end

  test "GET /api/datasets/:id with a proxy resource", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()
    setup_empty_history_resources()

    json = conn |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id)) |> json_response(200)

    download_url = resource.url
    assert [%{"url" => ^download_url}] = json["resources"]
  end

  test "GET /api/datasets/:id with a proxy resource and a token", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()
    %DB.Token{secret: secret} = insert_token()

    setup_empty_history_resources()

    json =
      conn
      |> put_req_header("authorization", secret)
      |> get(Helpers.dataset_path(conn, :by_id, dataset.datagouv_id))
      |> json_response(200)

    auth_url = resource.url <> "?token=#{secret}"
    assert [%{"url" => ^auth_url}] = json["resources"]
  end

  test "GET /api/datasets with a proxy resource and a token", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()
    %DB.Token{secret: secret} = insert_token()

    json =
      conn
      |> put_req_header("authorization", secret)
      |> get(Helpers.dataset_path(conn, :datasets))
      |> json_response(200)

    auth_url = resource.url <> "?token=#{secret}"
    assert [%{"url" => ^auth_url}] = json |> hd() |> Map.get("resources")
  end

  test "covered_area" do
    dataset =
      insert(:dataset,
        declarative_spatial_areas: [
          build(:administrative_division, nom: "A", insee: "123", type_insee: "epci_123", type: :epci),
          build(:administrative_division, nom: "B", insee: "456", type_insee: "region_456", type: :region)
        ]
      )
      |> DB.Repo.preload(:declarative_spatial_areas)

    assert TransportWeb.API.DatasetController.covered_area(dataset) == [
             %{type: :region, nom: "B", insee: "456"},
             %{type: :epci, nom: "A", insee: "123"}
           ]
  end

  describe "geojson_by_id" do
    test "it works", %{conn: conn} do
      commune =
        insert(:administrative_division,
          type: :commune,
          type_insee: "commune_12345",
          insee: "12345",
          nom: "Test Commune",
          geom: %Geo.Point{coordinates: {1, 1}, srid: 4326}
        )

      departement =
        insert(:administrative_division,
          type: :departement,
          type_insee: "departement_123",
          insee: "123",
          nom: "Test Département",
          geom: %Geo.Polygon{
            coordinates: [
              [
                {55.0, 3.0},
                {60.0, 3.0},
                {60.0, 5.0},
                {55.0, 5.0},
                {55.0, 3.0}
              ]
            ],
            srid: 4326,
            properties: %{}
          }
        )

      dataset = insert(:dataset, declarative_spatial_areas: [departement, commune])

      json =
        conn
        |> get(Helpers.dataset_path(conn, :geojson_by_id, dataset.datagouv_id))
        |> json_response(200)

      assert json == %{
               "features" => [
                 %{
                   "geometry" => %{
                     "coordinates" => [[[55.0, 3.0], [60.0, 3.0], [60.0, 5.0], [55.0, 5.0], [55.0, 3.0]]],
                     "crs" => %{"properties" => %{"name" => "EPSG:4326"}, "type" => "name"},
                     "type" => "Polygon"
                   },
                   "properties" => %{"name" => "Test Département"},
                   "type" => "Feature"
                 },
                 %{
                   "geometry" => %{
                     "coordinates" => [1.0, 1.0],
                     "crs" => %{"properties" => %{"name" => "EPSG:4326"}, "type" => "name"},
                     "type" => "Point"
                   },
                   "properties" => %{"name" => "Test Commune"},
                   "type" => "Feature"
                 }
               ],
               "name" => "Dataset #{dataset.slug}",
               "type" => "FeatureCollection"
             }
    end

    test "404", %{conn: conn} do
      json =
        conn
        |> get(Helpers.dataset_path(conn, :geojson_by_id, "notfound"))
        |> json_response(404)

      assert json == "dataset not found"
    end
  end

  defp setup_empty_history_resources do
    expect(Transport.History.Fetcher.Mock, :history_resources, fn %DB.Dataset{}, options ->
      assert Keyword.equal?(options,
               preload_validations: false,
               max_records: 25,
               fetch_mode: :all,
               only_metadata: false
             )

      []
    end)
  end

  defp resource_page_url(%DB.Resource{id: id}) do
    TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id)
  end
end
