defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
  import ExUnit.CaptureLog

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
      html_response = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200)
      assert html_response =~ "Documentation"
      refute html_response =~ "Conversions automatiques"
    end
  end

  test "dataset details with a NeTEx conversion", %{conn: conn} do
    dataset = insert(:dataset, type: "public-transit", is_active: true)
    resource = insert(:resource, format: "GTFS", url: "https://example.com", dataset: dataset)
    insert(:resource_history, resource_id: resource.id, payload: %{"uuid" => uuid = Ecto.UUID.generate()})

    insert(:data_conversion,
      resource_history_uuid: uuid,
      convert_from: "GTFS",
      convert_to: "NeTEx",
      payload: %{"permanent_url" => conversion_url = "https://super-cellar-url.com/netex"}
    )

    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)

    with_mocks [
      {Datagouvfr.Client.Reuses, [], [get: fn _dataset -> {:ok, []} end]},
      {Datagouvfr.Client.Discussions, [], [get: fn _id -> nil end]}
    ] do
      html_response = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200)
      assert html_response =~ "Conversions automatiques"
      assert html_response =~ "NeTEx"
      assert html_response =~ conversion_path(conn, :get, resource.id, :NeTEx)
      refute html_response =~ conversion_url
      refute html_response =~ "GeoJSON"
    end
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

  describe "climate and resilience bill" do
    test "displayed for public-transit", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index, type: "public-transit"))
      doc = conn |> html_response(200) |> Floki.parse_document!()
      [msg] = Floki.find(doc, "#climate-resilience-bill-panel")

      assert Floki.text(msg) =~
               "Certaines données de cette catégorie font l'objet d'une intégration obligatoire depuis décembre 2022"
    end

    test "not displayed for locations", %{conn: conn} do
      conn = conn |> get(dataset_path(conn, :index, type: "locations"))
      doc = conn |> html_response(200) |> Floki.parse_document!()
      assert [] == Floki.find(doc, "#climate-resilience-bill-panel")
    end
  end

  test "has_validity_period?" do
    assert TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{
             validations: [
               %{metadata: %DB.ResourceMetadata{metadata: %{"start_date" => "2022-02-17", "end_date" => "2023-02-17"}}}
             ]
           })

    # end_date is missing
    refute TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{
             validations: [%{metadata: %DB.ResourceMetadata{metadata: %{"start_date" => "2022-02-17"}}}]
           })

    refute TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{
             validations: [%{metadata: %DB.ResourceMetadata{metadata: %{"start_date" => nil}}}]
           })

    refute TransportWeb.DatasetView.has_validity_period?(%DB.ResourceHistory{})
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
    assert conn |> html_response(200) =~ "Données temps réel"
  end

  describe "licence description" do
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
      assert conn |> html_response(200) =~ "Règles de la communauté OSM"
    end

    test "licence ouverte licence", %{conn: conn} do
      insert(:dataset, %{slug: slug = "dataset-slug", licence: "lov2"})

      set_empty_mocks()

      conn = conn |> get(dataset_path(conn, :details, slug))
      assert conn |> html_response(200) =~ "Licence Ouverte — version 2.0"
      refute conn |> html_response(200) =~ "Conditions Particulières"
    end
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

  test "with an inactive dataset", %{conn: conn} do
    insert(:dataset, is_active: false, slug: slug = "dataset-slug")

    set_empty_mocks()

    assert conn |> get(dataset_path(conn, :details, slug)) |> html_response(404) =~
             "Ce jeu de données a été supprimé de data.gouv.fr"
  end

  test "with an archived dataset", %{conn: conn} do
    insert(:dataset, is_active: true, slug: slug = "dataset-slug", archived_at: DateTime.utc_now())

    set_empty_mocks()

    assert conn |> get(dataset_path(conn, :details, slug)) |> html_response(200) =~
             "Ce jeu de données a été archivé de data.gouv.fr"
  end

  test "redirects when the slug changed on data.gouv.fr", %{conn: conn} do
    dataset =
      insert(:dataset, is_active: true, slug: old_slug = "old_slug", datagouv_id: datagouv_id = Ecto.UUID.generate())

    new_slug = "new_slug"
    url = "https://demo.data.gouv.fr/api/1/datasets/#{new_slug}/"

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{id: datagouv_id, slug: new_slug})}}
    end)

    {path, _} = with_log(fn -> conn |> get(dataset_path(conn, :details, new_slug)) |> redirected_to(302) end)

    assert path == dataset_path(conn, :details, old_slug)

    assert %Dataset{slug: ^old_slug} = DB.Repo.reload!(dataset)
  end

  test "404 when data.gouv.fr's API returns a 404", %{conn: conn} do
    insert(:dataset, is_active: true, slug: "old_slug")
    slug_404 = "slug_404"
    url = "https://demo.data.gouv.fr/api/1/datasets/#{slug_404}/"

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
    end)

    with_log(fn -> conn |> get(dataset_path(conn, :details, slug_404)) |> html_response(404) end)
  end

  test "dataset#details with an ID or datagouv_id redirects to slug", %{conn: conn} do
    dataset = insert(:dataset, is_active: true, slug: Ecto.UUID.generate(), datagouv_id: Ecto.UUID.generate())

    [dataset.id, dataset.datagouv_id]
    |> Enum.each(fn param ->
      {path, _} = with_log(fn -> conn |> get(dataset_path(conn, :details, param)) |> redirected_to(302) end)
      assert path == dataset_path(conn, :details, dataset.slug)
    end)
  end

  test "dataset#details uses DatasetHistory when passed an old slug", %{conn: conn} do
    dataset = insert(:dataset, is_active: true, slug: Ecto.UUID.generate(), datagouv_id: Ecto.UUID.generate())

    insert(:dataset_history, dataset_id: dataset.id, payload: %{slug: old_slug = Ecto.UUID.generate()})

    {path, _} = with_log(fn -> conn |> get(dataset_path(conn, :details, old_slug)) |> redirected_to(302) end)
    assert path == dataset_path(conn, :details, dataset.slug)
  end

  test "dataset#details with an old slug when DatasetHistory returns multiple possible datasets", %{conn: conn} do
    dataset = insert(:dataset, is_active: true, slug: Ecto.UUID.generate(), datagouv_id: Ecto.UUID.generate())
    dataset2 = insert(:dataset, is_active: true, slug: Ecto.UUID.generate(), datagouv_id: Ecto.UUID.generate())
    old_slug = Ecto.UUID.generate()

    insert(:dataset_history, dataset_id: dataset.id, payload: %{slug: old_slug})
    insert(:dataset_history, dataset_id: dataset2.id, payload: %{slug: old_slug})

    with_log(fn -> conn |> get(dataset_path(conn, :details, old_slug)) |> html_response(404) end)
  end

  test "dataset#details with resources_related for gtfs-rt resources", %{conn: conn} do
    dataset = insert(:dataset, is_active: true, slug: slug = "dataset-slug")
    gtfs = insert(:resource, dataset: dataset, url: "https://example.com/gtfs.zip", format: "GTFS")
    gtfs_rt = insert(:resource, dataset: dataset, url: "https://example.com/gtfs-rt", format: "gtfs-rt")
    insert(:resource_related, resource_src: gtfs_rt, resource_dst: gtfs, reason: :gtfs_rt_gtfs)

    set_empty_mocks()

    assert conn |> get(dataset_path(conn, :details, slug)) |> html_response(200) =~
             ~s{<i class="icon fa fa-link" aria-hidden="true"></i>\n<a class="dark" href="#{resource_path(conn, :details, gtfs.id)}">GTFS</a>}
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
      inserted_at: Transport.Jobs.GTFSRTMetadataJob.datetime_limit() |> DateTime.add(-5)
    )

    assert %{resource_id_1 => MapSet.new(["a", "b"]), resource_id_2 => MapSet.new(["a", "c", "d"])} ==
             dataset |> TransportWeb.DatasetController.gtfs_rt_entities()
  end

  test "get_licences" do
    insert(:dataset, licence: "lov2", type: "low-emission-zones")
    insert(:dataset, licence: "fr-lo", type: "low-emission-zones")
    insert(:dataset, licence: "odc-odbl", type: "low-emission-zones")
    insert(:dataset, licence: "odc-odbl", type: "public-transit")

    assert [%{count: 1, licence: "odc-odbl"}] ==
             TransportWeb.DatasetController.get_licences(%{"type" => "public-transit"})

    assert [%{count: 2, licence: "licence-ouverte"}, %{count: 1, licence: "odc-odbl"}] ==
             TransportWeb.DatasetController.get_licences(%{"type" => "low-emission-zones"})
  end

  defp set_empty_mocks do
    Datagouvfr.Client.Reuses.Mock |> expect(:get, fn _ -> {:ok, []} end)
    Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _ -> %{} end)
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)
  end
end
