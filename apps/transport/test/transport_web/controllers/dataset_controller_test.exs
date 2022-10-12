defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory

  import Mock
  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Datagouvfr.Client.Reuses.Mock, Datagouvfr.Client.Reuses)
    Mox.stub_with(Datagouvfr.Client.Discussions.Mock, Datagouvfr.Client.Discussions)
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    :ok
  end

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "Datasets details page loads even when data.gouv is down", %{conn: conn} do
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)
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

  test "dataset details with a documentation resource", %{conn: conn} do
    dataset = insert(:dataset, aom: insert(:aom, composition_res_id: 157))
    resource = insert(:resource, type: "documentation", url: "https://example.com", dataset: dataset)

    dataset = dataset |> DB.Repo.preload(:resources)

    assert DB.Resource.is_documentation?(resource)
    assert Enum.empty?(TransportWeb.DatasetView.other_official_resources(dataset))
    assert 1 == Enum.count(TransportWeb.DatasetView.official_documentation_resources(dataset))

    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)

    with_mocks [
      {Datagouvfr.Client.Reuses, [], [get: fn _dataset -> {:ok, []} end]},
      {Datagouvfr.Client.Discussions, [], [get: fn _id -> nil end]}
    ] do
      conn = conn |> get(dataset_path(conn, :details, dataset.slug))
      assert html_response(conn, 200) =~ "Documentation"
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
        custom_title: "title",
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
                 "type" => "main",
                 "format" => "GTFS",
                 "modes" => [],
                 "original_url" => "https://link.to/file.zip",
                 "updated" => "",
                 "url" => "https://static.data.gouv.fr/foo"
               },
               %{
                 "datagouv_id" => "2",
                 "features" => [],
                 "type" => "main",
                 "format" => "geojson",
                 "modes" => [],
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

  test "show GTFS number of errors", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, %{slug: slug = "dataset-slug", aom: build(:aom)})

    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id, format: "GTFS", url: "url"})

    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      result: %{"Slow" => [%{"severity" => "Information"}]},
      metadata: %DB.ResourceMetadata{metadata: %{}, modes: ["ferry", "bus"]}
    })

    set_empty_mocks()

    conn = conn |> get(dataset_path(conn, :details, slug))
    assert conn |> html_response(200) =~ "1 information"
    assert conn |> html_response(200) =~ "ferry"
  end

  test "show number of errors for a GBFS", %{conn: conn} do
    dataset = insert(:dataset, %{slug: "dataset-slug"})

    resource = insert(:resource, %{dataset_id: dataset.id, format: "gbfs", url: "url"})

    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource.id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.GBFSValidator.validator_name(),
      result: %{"errors_count" => 1},
      metadata: %{metadata: %{}}
    })

    set_empty_mocks()

    conn = conn |> get(dataset_path(conn, :details, dataset.slug))
    assert conn |> html_response(200) =~ "1 erreur"
  end

  test "GTFS-RT without validation", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, %{slug: slug = "dataset-slug"})
    insert(:resource, %{dataset_id: dataset_id, format: "gtfs-rt", url: "url"})

    set_empty_mocks()

    conn = conn |> get(dataset_path(conn, :details, slug))
    assert conn |> html_response(200) =~ "Ressources temps réel"
  end

  test "ODbL licence with specific conditions", %{conn: conn} do
    insert(:dataset, %{slug: slug = "dataset-slug", licence: "odc-odbl"})

    set_empty_mocks()

    conn = conn |> get(dataset_path(conn, :details, slug))
    assert conn |> html_response(200) =~ "Conditions Particulières"
  end

  test "ODbL licence with openstreetmap tag", %{conn: conn} do
    insert(:dataset, %{slug: slug = "dataset-slug", licence: "odc-odbl", tags: ["openstreetmap"]})

    set_empty_mocks()

    conn = conn |> get(dataset_path(conn, :details, slug))
    refute conn |> html_response(200) =~ "Conditions Particulières"
  end

  test "does not crash when validation_performed is false", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, %{slug: slug = "dataset-slug"})

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        format: "geojson",
        schema_name: schema_name = "etalab/zfe",
        url: "https://example.com/file"
      })

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 1, fn -> %{schema_name => %{"title" => "foo"}} end)

    insert(:multi_validation, %{
      resource_history: insert(:resource_history, %{resource_id: resource_id}),
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"validation_performed" => false}
    })

    set_empty_mocks()

    conn |> get(dataset_path(conn, :details, slug)) |> html_response(200)
  end

  test "gtfs-rt entities" do
    dataset = %{id: dataset_id} = insert(:dataset, type: "public-transit")
    %{id: resource_id_1} = insert(:resource, dataset_id: dataset_id, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_id_1, features: ["a", "b"])
    %{id: resource_id_2} = insert(:resource, dataset_id: dataset_id, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_id_2, features: ["a", "c"])
    insert(:resource_metadata, resource_id: resource_id_2, features: ["d"])

    # too old
    %{id: resource_id_3} = insert(:resource, dataset_id: dataset_id, format: "gtfs-rt")

    insert(:resource_metadata,
      resource_id: resource_id_3,
      features: ["e"],
      inserted_at: Transport.Jobs.GTFSRTEntitiesJob.datetime_limit() |> DateTime.add(-5)
    )

    assert %{resource_id_1 => MapSet.new(["a", "b"]), resource_id_2 => MapSet.new(["a", "c", "d"])} ==
             dataset |> TransportWeb.DatasetController.gtfs_rt_entities()
  end

  defp set_empty_mocks do
    Datagouvfr.Client.Reuses.Mock |> expect(:get, fn _ -> {:ok, []} end)
    Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _ -> %{} end)
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)
  end
end
