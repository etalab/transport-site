defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
  import ExUnit.CaptureLog

  import Mock
  import Mox

  @pan_org_id "5abca8d588ee386ee6ece479"

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Datagouvfr.Client.Reuses.Mock, Datagouvfr.Client.Reuses)
    Mox.stub_with(Datagouvfr.Client.Discussions.Mock, Datagouvfr.Client.Discussions)
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    :ok
  end

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "dataset details with a documentation resource", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, type: "documentation", url: "https://example.com", dataset: dataset)

    dataset = dataset |> DB.Repo.preload(:resources)

    assert DB.Resource.documentation?(resource)
    assert Enum.empty?(TransportWeb.DatasetView.other_official_resources(dataset))
    assert 1 == Enum.count(TransportWeb.DatasetView.official_documentation_resources(dataset))

    mock_empty_history_resources()

    with_mocks [
      {Datagouvfr.Client.Reuses, [], [get: fn _dataset -> {:ok, []} end]},
      {Datagouvfr.Client.Discussions, [], [get: fn _id -> nil end]}
    ] do
      html_response = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200)
      assert html_response =~ "Documentation"
      refute html_response =~ "Conversions automatiques"
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

  test "custom logo is displayed", %{conn: conn} do
    dataset =
      insert(:dataset,
        type: "public-transit",
        is_active: true,
        custom_title: custom_title = "Super JDD",
        custom_logo: custom_logo = "https://example.com/logo_#{Ecto.UUID.generate()}.png"
      )

    assert DB.Dataset.logo(dataset) == custom_logo

    assert [
             {"div", [{"class", "dataset__image"}, {"data-provider", _}],
              [{"img", [{"alt", ^custom_title}, {"src", ^custom_logo}], []}]}
           ] =
             conn
             |> get(dataset_path(conn, :index))
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find(".dataset__image")
  end

  describe "heart icons" do
    test "not displayed when logged out", %{conn: conn} do
      insert(:dataset, type: "public-transit", is_active: true)

      assert [
               {"div", [{"class", "dataset__type"}],
                [{"img", [{"alt", "public-transit"}, {"src", "/images/icons/bus.svg"}], []}]}
             ] =
               conn
               |> get(dataset_path(conn, :index))
               |> html_response(200)
               |> Floki.parse_document!()
               |> Floki.find(".dataset__type")
    end

    test "non admin", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

      insert(:dataset, custom_title: "A")
      followed_dataset = insert(:dataset, custom_title: "B")
      insert(:dataset_follower, contact_id: contact.id, dataset_id: followed_dataset.id)

      document =
        conn
        |> init_test_session(%{current_user: %{"id" => datagouv_user_id, "is_admin" => false}})
        |> get(dataset_path(conn, :index))
        |> html_response(200)
        |> Floki.parse_document!()

      assert ["A", "B"] == dataset_titles(document)

      assert [
               {"i", [{"class", "fa fa-heart"}], []},
               {"i", [{"class", "fa fa-heart following"}], []}
             ] == Floki.find(document, ".dataset__type i.fa-heart")
    end

    test "admin: displayed accordingly for producer, following and nothing", %{conn: conn} do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      insert(:dataset, organization_id: organization.id, custom_title: "A")
      followed_dataset = insert(:dataset, custom_title: "B")
      insert(:dataset_follower, contact_id: contact.id, dataset_id: followed_dataset.id)
      insert(:dataset, custom_title: "C")

      document =
        conn
        |> init_test_session(%{current_user: %{"id" => datagouv_user_id, "is_admin" => true}})
        |> get(dataset_path(conn, :index))
        |> html_response(200)
        |> Floki.parse_document!()

      assert ["A", "B", "C"] == dataset_titles(document)

      assert [
               {"i", [{"class", "fa fa-heart producer"}], []},
               {"i", [{"class", "fa fa-heart following"}], []},
               {"i", [{"class", "fa fa-heart"}], []}
             ] =
               Floki.find(document, ".dataset__type i.fa-heart")
    end
  end

  describe "header links" do
    test "logged out", %{conn: conn} do
      mock_empty_history_resources()

      dataset = insert(:dataset)

      assert [
               {"a",
                [
                  {"href", page_path(conn, :infos_reutilisateurs, utm_campaign: "dataset_details")},
                  {"target", "_blank"}
                ], ["Espace réutilisateur"]}
             ] ==
               conn
               |> init_test_session(%{force_display_reuser_space: true})
               |> dataset_header_links(dataset)
    end

    test "logged-in, producer", %{conn: conn} do
      mock_empty_history_resources()
      organization = insert(:organization)

      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

      dataset = insert(:dataset, organization_id: organization.id)

      assert [
               {"a",
                [
                  {"href", espace_producteur_path(conn, :edit_dataset, dataset.id, utm_campaign: "dataset_details")},
                  {"target", "_blank"}
                ], ["Espace producteur"]}
             ] ==
               conn
               |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
               |> dataset_header_links(dataset)
    end

    test "logged-in, follows the dataset", %{conn: conn} do
      mock_empty_history_resources()
      contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
      dataset = insert(:dataset)
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      assert [
               {"a",
                [
                  {"href", reuser_space_path(conn, :datasets_edit, dataset.id, utm_campaign: "dataset_details")},
                  {"target", "_blank"}
                ], ["Espace réutilisateur"]}
             ] ==
               conn
               |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
               |> dataset_header_links(dataset)
    end

    test "logged-in, does not follow the dataset", %{conn: conn} do
      mock_empty_history_resources()
      insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
      dataset = insert(:dataset)

      assert [
               {"a",
                [
                  {"href", reuser_space_path(conn, :espace_reutilisateur, utm_campaign: "dataset_details")},
                  {"target", "_blank"}
                ], ["Espace réutilisateur"]}
             ] ==
               conn
               |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
               |> dataset_header_links(dataset)
    end

    test "for an admin, producer", %{conn: conn} do
      mock_empty_history_resources()
      organization = insert(:organization)

      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

      dataset = insert(:dataset, organization_id: organization.id)

      assert [
               {"a", [{"href", backoffice_page_path(conn, :edit, dataset.id)}], ["Backoffice"]},
               {"a",
                [
                  {"href", espace_producteur_path(conn, :edit_dataset, dataset.id, utm_campaign: "dataset_details")},
                  {"target", "_blank"}
                ], ["Espace producteur"]}
             ] ==
               conn
               |> init_test_session(%{
                 current_user: %{"id" => datagouv_user_id, "is_admin" => true}
               })
               |> dataset_header_links(dataset)
    end
  end

  test "dataset_heart_values" do
    organization = insert(:organization)

    contact =
      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

    producer_dataset = insert(:dataset, organization_id: organization.id)
    insert(:dataset_follower, contact_id: contact.id, dataset: followed_dataset = insert(:dataset))
    nothing_dataset = insert(:dataset)

    datasets = DB.Repo.all(DB.Dataset)

    assert %{
             producer_dataset.id => :producer,
             followed_dataset.id => :following,
             nothing_dataset.id => nil
           } == TransportWeb.DatasetController.dataset_heart_values(%{"id" => datagouv_user_id}, datasets)
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
    dataset = insert(:dataset)

    resource = insert(:resource, dataset: dataset, format: "GTFS", url: "url")

    resource_history = insert(:resource_history, resource: resource)

    result = %{"Slow" => [%{"severity" => "Information"}]}
    digest = Transport.Validators.GTFSTransport.digest(result)

    insert(:multi_validation,
      resource_history_id: resource_history.id,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      result: result,
      digest: digest,
      metadata: %DB.ResourceMetadata{metadata: %{}, modes: ["ferry", "bus"]}
    )

    mock_empty_history_resources()

    conn = conn |> get(dataset_path(conn, :details, dataset.slug))
    assert conn |> html_response(200) |> extract_resource_details() =~ "1 information"
    # Dataset modes are not displayed
    refute conn |> html_response(200) |> extract_resource_details() =~ "ferry"
  end

  test "show number of errors for a GBFS", %{conn: conn} do
    dataset = insert(:dataset, slug: "dataset-slug")

    resource = insert(:resource, dataset_id: dataset.id, format: "gbfs", url: "url")

    %{id: resource_history_id} = insert(:resource_history, resource_id: resource.id)

    result = %{"errors_count" => 1}
    digest = Transport.Validators.GBFSValidator.digest(result)

    insert(:multi_validation,
      resource_history_id: resource_history_id,
      validator: Transport.Validators.GBFSValidator.validator_name(),
      result: result,
      digest: digest,
      metadata: %{metadata: %{}}
    )

    mock_empty_history_resources()

    conn = conn |> get(dataset_path(conn, :details, dataset.slug))

    assert conn |> html_response(200) |> extract_resource_details() =~ "1 erreur"
  end

  test "show number of errors when validated with the MobilityData validator", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, format: "GTFS")
    resource_history = insert(:resource_history, resource_id: resource.id)

    insert(:multi_validation,
      resource_history: resource_history,
      validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
      digest: %{"stats" => %{"ERROR" => 1}, "max_severity" => %{"max_level" => "ERROR", "worst_occurrences" => 1}}
    )

    result = %{"Slow" => [%{"severity" => "Information"}]}
    digest = Transport.Validators.GTFSTransport.digest(result)

    insert(:multi_validation,
      resource_history: resource_history,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      result: result,
      digest: digest,
      metadata: %DB.ResourceMetadata{metadata: %{}, modes: ["ferry", "bus"]}
    )

    mock_empty_history_resources()

    conn = conn |> get(dataset_path(conn, :details, dataset.slug))

    assert conn |> html_response(200) |> extract_resource_details() =~ "1 erreur"
  end

  test "displays MobilityData if validated by both GTFS validators", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, format: "GTFS")

    insert(:multi_validation,
      resource_history: insert(:resource_history, resource_id: resource.id),
      validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
      digest: %{"stats" => %{"ERROR" => 1}, "max_severity" => %{"max_level" => "ERROR", "worst_occurrences" => 1}}
    )

    mock_empty_history_resources()

    conn = conn |> get(dataset_path(conn, :details, dataset.slug))

    assert conn |> html_response(200) |> extract_resource_details() =~ "1 erreur"
  end

  test "GBFS with a nil validation", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset_id: dataset.id, format: "gbfs", url: "url")
    %{id: resource_history_id} = insert(:resource_history, resource_id: resource.id)

    insert(:multi_validation,
      resource_history_id: resource_history_id,
      validator: Transport.Validators.GBFSValidator.validator_name(),
      result: nil,
      metadata: nil
    )

    mock_empty_history_resources()

    assert conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200)
  end

  test "show NeTEx number of errors", %{conn: conn} do
    issues = [%{"criticity" => "error"}]

    for version <- ["0.1.0", "0.2.0", "0.2.1"] do
      dataset = insert(:dataset)

      resource = insert(:resource, dataset: dataset, format: "NeTEx", url: "url")

      resource_history = insert(:resource_history, resource: resource)

      result =
        case version do
          "0.1.0" -> %{"xsd-1871" => issues}
          _ -> %{"xsd-schema" => issues}
        end

      results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)

      digest = results_adapter.digest(result)

      insert(:multi_validation,
        resource_history: resource_history,
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        validator_version: version,
        result: result,
        digest: digest,
        metadata: %DB.ResourceMetadata{
          metadata: %{"elapsed_seconds" => 42},
          modes: [],
          features: []
        }
      )

      mock_empty_history_resources()

      conn = conn |> get(dataset_path(conn, :details, dataset.slug))
      assert conn |> html_response(200) |> extract_resource_details() =~ "1 erreur"
    end
  end

  test "don't show NeTEx number of errors if no validation", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, slug: slug = "dataset-slug")

    %{id: resource_id} = insert(:resource, dataset_id: dataset_id, format: "NeTEx", url: "url")

    insert(:resource_history, resource_id: resource_id)

    mock_empty_history_resources()

    conn = conn |> get(dataset_path(conn, :details, slug))
    refute conn |> html_response(200) |> extract_resource_details() =~ "1 erreur"
  end

  test "GTFS-RT without validation", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, slug: slug = "dataset-slug")
    insert(:resource, dataset_id: dataset_id, format: "gtfs-rt", url: "url")

    mock_empty_history_resources()

    conn = conn |> get(dataset_path(conn, :details, slug))
    assert conn |> html_response(200) =~ "Données temps réel"
  end

  describe "licence description" do
    test "ODbL licence with specific conditions", %{conn: conn} do
      insert(:dataset, slug: slug = "dataset-slug", licence: "odc-odbl")

      mock_empty_history_resources()

      conn = conn |> get(dataset_path(conn, :details, slug))
      assert conn |> html_response(200) =~ "Conditions Particulières"
    end

    test "ODbL licence with openstreetmap tag", %{conn: conn} do
      insert(:dataset, slug: slug = "dataset-slug", licence: "odc-odbl", tags: ["openstreetmap"])

      mock_empty_history_resources()

      conn = conn |> get(dataset_path(conn, :details, slug))
      refute conn |> html_response(200) =~ "Conditions Particulières"
      assert conn |> html_response(200) =~ "Règles de la communauté OSM"
    end

    test "licence ouverte licence", %{conn: conn} do
      insert(:dataset, slug: slug = "dataset-slug", licence: "lov2")

      mock_empty_history_resources()

      conn = conn |> get(dataset_path(conn, :details, slug))
      assert conn |> html_response(200) =~ "Licence Ouverte — version 2.0"
      refute conn |> html_response(200) =~ "Conditions Particulières"
    end
  end

  test "does not crash when validation_performed is false", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, slug: slug = "dataset-slug")

    %{id: resource_id} =
      insert(:resource,
        dataset_id: dataset_id,
        format: "geojson",
        schema_name: schema_name = "etalab/zfe",
        url: "https://example.com/file"
      )

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 1, fn -> %{schema_name => %{"title" => "foo"}} end)

    insert(:multi_validation, %{
      resource_history: insert(:resource_history, resource_id: resource_id),
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"validation_performed" => false}
    })

    mock_empty_history_resources()

    conn |> get(dataset_path(conn, :details, slug)) |> html_response(200)
  end

  test "with an inactive dataset", %{conn: conn} do
    insert(:dataset, is_active: false, slug: slug = "dataset-slug")

    mock_empty_history_resources()

    assert conn |> get(dataset_path(conn, :details, slug)) |> html_response(404) =~
             "Ce jeu de données a été supprimé de data.gouv.fr"
  end

  test "with an archived dataset", %{conn: conn} do
    insert(:dataset, is_active: true, slug: slug = "dataset-slug", archived_at: DateTime.utc_now())

    mock_empty_history_resources()

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

    mock_empty_history_resources()

    assert conn |> get(dataset_path(conn, :details, slug)) |> html_response(200) =~
             ~s{<i class="icon fa fa-link" aria-hidden="true"></i>\n<a class="dark" href="#{resource_path(conn, :details, gtfs.id)}">GTFS</a>}
  end

  test "dataset#details with notifications sent recently", %{conn: conn} do
    dataset = insert(:dataset, is_active: true)

    insert_notification(%{
      dataset: dataset,
      role: :producer,
      reason: :expiration,
      email: Ecto.UUID.generate() <> "@example.com"
    })

    mock_empty_history_resources()

    doc = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200) |> Floki.parse_document!()
    [msg] = Floki.find(doc, "#notifications-sent")
    assert Floki.text(msg) =~ "Expiration de données"
  end

  test "dataset#details with a SIRI resource links to the query generator", %{conn: conn} do
    requestor_ref = Ecto.UUID.generate()
    dataset = insert(:dataset, is_active: true, slug: "dataset-slug", custom_tags: ["requestor_ref:#{requestor_ref}"])
    resource = insert(:resource, dataset: dataset, url: "https://example.com/siri", format: "SIRI")
    assert DB.Resource.requestor_ref(resource) == requestor_ref

    mock_empty_history_resources()
    {html, _} = with_log(fn -> conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200) end)

    assert html =~
             conn
             |> live_path(TransportWeb.Live.SIRIQuerierLive,
               endpoint_url: resource.url,
               requestor_ref: DB.Resource.requestor_ref(resource),
               query_template: "LinesDiscovery"
             )
             |> Phoenix.HTML.html_escape()
             |> Phoenix.HTML.safe_to_string()
  end

  test "quality indicators chart is displayed", %{conn: conn} do
    dataset = insert(:dataset, is_active: true)

    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now() |> DateTime.add(-24, :hour),
      score: 0.3,
      topic: :freshness
    )

    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now() |> DateTime.add(-1, :hour),
      score: 0.549,
      topic: :freshness
    )

    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now() |> DateTime.add(-3, :hour),
      score: 0.8,
      topic: :compliance
    )

    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now() |> DateTime.add(-1, :hour),
      score: nil,
      topic: :availability
    )

    mock_empty_history_resources()

    content = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200) |> Floki.parse_document!()

    refute content |> Floki.find("#quality-indicators") |> Enum.empty?()

    assert [
             {"table", [{"class", "table"}],
              [
                {"tr", [], [{"th", [], ["Conformité"]}, {"th", [], ["Fraicheur"]}]},
                {"tr", [], [{"td", [], ["80%"]}, {"td", [], ["55%"]}]}
              ]}
           ] == content |> Floki.find("#quality-indicators table")
  end

  describe "information & warning banners are displayed" do
    test "a seasonal dataset", %{conn: conn} do
      dataset = insert(:dataset, is_active: true, custom_tags: ["saisonnier", "foo"])
      assert TransportWeb.DatasetView.seasonal_warning?(dataset)

      dataset_has_banner_with_text(
        conn,
        dataset,
        "Le service de transport de ce jeu de donnée ne fonctionne pas toute l'année"
      )
    end

    test "a dataset with authentication required", %{conn: conn} do
      dataset = insert(:dataset, is_active: true, custom_tags: ["authentification_requise"])

      assert TransportWeb.DatasetView.authentication_required?(dataset)

      dataset_has_banner_with_text(
        conn,
        dataset,
        "Le producteur requiert une authentification pour accéder aux données"
      )
    end

    test "an experimental dataset", %{conn: conn} do
      dataset = insert(:dataset, is_active: true, custom_tags: ["experimental", "foo"])
      assert DB.Dataset.experimental?(dataset)

      dataset_has_banner_with_text(
        conn,
        dataset,
        "Ce jeu de données non officiel est publié à titre expérimental. Veuillez ne pas le réutiliser à des fins d’information voyageur."
      )
    end
  end

  test "custom logo is displayed when set", %{conn: conn} do
    dataset =
      insert(:dataset,
        is_active: true,
        custom_title: custom_title = "Super JDD",
        custom_full_logo: custom_full_logo = "https://example.com/logo_#{Ecto.UUID.generate()}.png"
      )

    mock_empty_history_resources()

    assert DB.Dataset.full_logo(dataset) == custom_full_logo

    assert [{"div", [{"class", "dataset__logo"}], [{"img", [{"alt", custom_title}, {"src", custom_full_logo}], []}]}] ==
             conn
             |> get(dataset_path(conn, :details, dataset.slug))
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find(".dataset__logo")
  end

  describe "dataset#details: favorite icon" do
    test "logged-out: nudge signup", %{conn: conn} do
      dataset = insert(:dataset)

      mock_empty_history_resources()

      assert [
               {"div", [{"class", "follow-dataset-icon"}], [{"i", [{"class", _}, {"phx-click", "nudge_signup"}], []}]}
             ] =
               conn
               |> get(dataset_path(conn, :details, dataset.slug))
               |> html_response(200)
               |> Floki.parse_document!()
               |> Floki.find(".follow-dataset-icon")
    end

    test "shown if you're an admin", %{conn: conn} do
      dataset = insert(:dataset)
      insert_contact(%{datagouv_user_id: contact_datagouv_id = Ecto.UUID.generate()})

      mock_empty_history_resources()

      assert [
               {"div", [{"class", "follow-dataset-icon"}],
                [
                  {"div", [{"class", "tooltip"}],
                   [
                     {"i", [{"class", _}, {"phx-click", "follow"}], []},
                     {"span", [{"class", "tooltiptext left"}], ["Suivre ce jeu de données"]}
                   ]}
                ]}
             ] =
               conn
               |> init_test_session(%{current_user: %{"is_admin" => true, "id" => contact_datagouv_id}})
               |> get(dataset_path(conn, :details, dataset.slug))
               |> html_response(200)
               |> Floki.parse_document!()
               |> Floki.find(".follow-dataset-icon")
    end
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
    insert(:dataset, licence: "lov2", type: "road-data")
    insert(:dataset, licence: "fr-lo", type: "road-data")
    insert(:dataset, licence: "odc-odbl", type: "road-data")
    insert(:dataset, licence: "odc-odbl", type: "public-transit")

    assert [%{count: 1, licence: "odc-odbl"}] ==
             TransportWeb.DatasetController.get_licences(%{"type" => "public-transit"})

    assert [%{count: 2, licence: "licence-ouverte"}, %{count: 1, licence: "odc-odbl"}] ==
             TransportWeb.DatasetController.get_licences(%{"type" => "road-data"})
  end

  test "hidden datasets", %{conn: conn} do
    hidden_dataset = insert(:dataset, is_hidden: true, is_active: true)

    # Dataset is not listed
    refute conn
           |> get(dataset_path(conn, :index))
           |> html_response(200) =~ hidden_dataset.custom_title

    mock_empty_history_resources()

    # Dataset can be seen on the details page, with a banner
    [{"div", [{"class", "notification full-width"}], [content]}] =
      conn
      |> get(dataset_path(conn, :details, hidden_dataset.slug))
      |> html_response(200)
      |> Floki.parse_document!()
      |> Floki.find(".notification")

    assert content =~ "Ce jeu de données est masqué"
  end

  test "dataset-page-title", %{conn: conn} do
    [
      {%{"type" => "public-transit"}, "Transport public collectif"}
    ]
    |> Enum.each(fn {params, expected_title} ->
      title =
        conn
        |> get(dataset_path(conn, :index, params))
        |> html_response(200)
        |> dataset_page_title()

      assert title == expected_title
    end)
  end

  test "resources_history_csv", %{conn: conn} do
    # Using the real implementation to test end-to-end
    Mox.stub_with(Transport.History.Fetcher.Mock, Transport.History.Fetcher.Database)

    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset)
    other_resource = insert(:resource, dataset: dataset)
    # another resource, no history for this one
    insert(:resource, dataset: dataset, format: "gtfs-rt")

    rh1 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{"foo" => "bar", "permanent_url" => "https://example.com/1"}
      )

    mv =
      insert(:multi_validation,
        resource_history_id: rh1.id,
        validator: "validator_name",
        result: %{"validation_details" => 42}
      )

    insert(:resource_metadata, multi_validation_id: mv.id, metadata: %{"metadata" => 1337})

    # resource_id is nil, but dataset_id is filled in the payload
    # no resource_metadata/multi_validation associated
    rh2 =
      insert(:resource_history,
        resource_id: nil,
        payload: %{"dataset_id" => dataset.id, "bar" => "baz", "permanent_url" => "https://example.com/2"}
      )

    # another resource for this dataset
    # no resource_metadata/multi_validation associated
    rh3 =
      insert(:resource_history,
        resource_id: other_resource.id,
        payload: %{"dataset_id" => dataset.id, "permanent_url" => "https://example.com/3"}
      )

    # Check that we sent a chunked response with the expected CSV content
    %Plug.Conn{state: :chunked} =
      response =
      conn
      |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
      |> get(dataset_path(conn, :resources_history_csv, dataset.id))

    content = response(response, 200)

    # Check CSV header
    assert content |> String.split("\r\n") |> hd() ==
             "resource_history_id,resource_id,permanent_url,payload,inserted_at"

    # Check CSV content
    assert [content] |> CSV.decode!(headers: true) |> Enum.to_list() == [
             %{
               "inserted_at" => to_string(rh3.inserted_at),
               "payload" => Jason.encode!(rh3.payload),
               "permanent_url" => "https://example.com/3",
               "resource_history_id" => to_string(rh3.id),
               "resource_id" => to_string(rh3.resource_id)
             },
             %{
               "inserted_at" => to_string(rh2.inserted_at),
               "payload" => Jason.encode!(rh2.payload),
               "permanent_url" => "https://example.com/2",
               "resource_history_id" => to_string(rh2.id),
               "resource_id" => to_string(rh2.resource_id)
             },
             %{
               "inserted_at" => to_string(rh1.inserted_at),
               "payload" => Jason.encode!(rh1.payload),
               "permanent_url" => "https://example.com/1",
               "resource_history_id" => to_string(rh1.id),
               "resource_id" => to_string(rh1.resource_id)
             }
           ]

    assert response_content_type(response, :csv) == "text/csv; charset=utf-8"

    assert Plug.Conn.get_resp_header(response, "content-disposition") == [
             ~s(attachment; filename="historisation-dataset-#{dataset.id}-#{Date.utc_today() |> Date.to_iso8601()}.csv")
           ]

    assert [
             %DB.FeatureUsage{
               feature: :download_resource_history,
               contact_id: ^contact_id,
               metadata: %{"dataset_id" => ^dataset_id}
             }
           ] = DB.FeatureUsage |> DB.Repo.all()
  end

  describe "Legal owner display" do
    test "dataset#details with no legal owners", %{conn: conn} do
      dataset = insert(:dataset, is_active: true)

      mock_empty_history_resources()

      doc = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200) |> Floki.parse_document!()
      refute Floki.text(doc) =~ "Données sous la responsabilité de"
    end

    test "dataset#details with AOM legal owner", %{conn: conn} do
      aom = insert(:aom, nom: "Angers Métropole", siren: "siren")
      dataset = insert(:dataset, is_active: true, legal_owners_aom: [aom])

      mock_empty_history_resources()

      doc = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200) |> Floki.parse_document!()
      assert Floki.text(doc) =~ "Données sous la responsabilité de"
      assert Floki.text(doc) =~ "Angers Métropole"
    end

    test "dataset#details with both Region and AOM legal owner", %{conn: conn} do
      region = DB.Region |> Ecto.Query.where(insee: "52") |> DB.Repo.one!()
      aom = insert(:aom, nom: "Angers Métropole", siren: "siren")
      dataset = insert(:dataset, is_active: true, legal_owners_aom: [aom], legal_owners_region: [region])

      mock_empty_history_resources()

      doc = conn |> get(dataset_path(conn, :details, dataset.slug)) |> html_response(200) |> Floki.parse_document!()
      assert Floki.text(doc) =~ "Données sous la responsabilité de"
      # Region is displayed first
      assert Floki.text(doc) =~ "Pays de la Loire, Angers Métropole"
    end
  end

  test "dataset#details, PAN resource, logged-in user with a default token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    assert resource |> DB.Repo.preload(:dataset) |> DB.Resource.pan_resource?()

    contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    token = insert_token()
    insert(:default_token, contact: contact, token: token)

    mock_empty_history_resources()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id, token: token.secret)] ==
             conn
             |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> dataset_href_download_button(dataset)
  end

  test "dataset#details, PAN resource, logged-in user without a default token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    assert resource |> DB.Repo.preload(:dataset) |> DB.Resource.pan_resource?()

    organization = insert(:organization)

    insert_contact(%{
      datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
      organizations: [organization |> Map.from_struct()]
    })

    insert_token(%{organization_id: organization.id})

    mock_empty_history_resources()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn
             |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> dataset_href_download_button(dataset)
  end

  test "dataset#details, PAN resource, logged-out user", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    assert resource |> DB.Repo.preload(:dataset) |> DB.Resource.pan_resource?()

    mock_empty_history_resources()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn |> dataset_href_download_button(dataset)
  end

  test "dataset#details, dataset with experimentation tag, logged-in user with a default token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    token = insert_token()
    insert(:default_token, contact: contact, token: token)

    mock_empty_history_resources()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id, token: token.secret)] ==
             conn
             |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> dataset_href_download_button(dataset)
  end

  test "dataset#details, dataset with experimentation tag, logged-in user without a default token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    organization = insert(:organization)

    insert_contact(%{
      datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
      organizations: [organization |> Map.from_struct()]
    })

    insert_token(%{organization_id: organization.id})

    mock_empty_history_resources()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn
             |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> dataset_href_download_button(dataset)
  end

  test "dataset#details, dataset with experimentation tag, logged-out user", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    mock_empty_history_resources()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn |> dataset_href_download_button(dataset)
  end

  test "dataset#details, dataset with experimentation tag, real-time resource", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, url: "https://example.com/gbfs", format: "gbfs", dataset: dataset)

    assert DB.Resource.real_time?(resource)
    mock_empty_history_resources()

    assert [resource.url] == conn |> dataset_href_download_button(dataset)
  end

  test "dataset#details, proxy resource, logged-in user with a default token", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()

    contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    token = insert_token()
    insert(:default_token, contact: contact, token: token)

    mock_empty_history_resources()

    assert [resource.url <> "?token=#{token.secret}"] ==
             conn
             |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> dataset_href_download_button(dataset)
  end

  test "dataset#details, proxy resource, logged-in user without a default token", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()

    organization = insert(:organization)

    insert_contact(%{
      datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
      organizations: [organization |> Map.from_struct()]
    })

    insert_token(%{organization_id: organization.id})

    mock_empty_history_resources()

    assert [resource.url] ==
             conn
             |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> dataset_href_download_button(dataset)
  end

  test "dataset#details, proxy resource, logged-out user", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()

    mock_empty_history_resources()

    assert [resource.url] ==
             conn |> dataset_href_download_button(dataset)
  end

  test "dataset#details, territories", %{conn: conn} do
    commune =
      insert(:administrative_division,
        type: :commune,
        type_insee: "commune_12345",
        insee: "12345",
        nom: "Test Commune"
      )

    departement =
      insert(:administrative_division,
        type: :departement,
        type_insee: "departement_123",
        insee: "123",
        nom: "Test Département"
      )

    dataset = insert(:dataset, declarative_spatial_areas: [departement, commune])

    mock_empty_history_resources()

    conn
    |> get(dataset_path(conn, :details, dataset.slug))
    |> html_response(200) =~ "Test Département, Test Commune"
  end

  def dataset_href_download_button(%Plug.Conn{} = conn, %DB.Dataset{} = dataset) do
    conn
    |> get(dataset_path(conn, :details, dataset.slug))
    |> html_response(200)
    |> Floki.parse_document!()
    |> Floki.find("a.download-button")
    |> hd()
    |> Floki.attribute("href")
  end

  defp dataset_page_title(content) do
    content
    |> Floki.parse_document!()
    |> Floki.find(".dataset-page-title h1")
    |> Floki.text()
  end

  defp mock_empty_history_resources do
    Transport.History.Fetcher.Mock
    |> expect(:history_resources, fn _, options ->
      assert Keyword.equal?(options, preload_validations: true, max_records: 25, fetch_mode: :all, only_metadata: true)
      []
    end)
  end

  defp dataset_titles(document) do
    document |> Floki.find(".dataset__title > a") |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp dataset_header_links(%Plug.Conn{} = conn, %DB.Dataset{} = dataset) do
    conn
    |> get(dataset_path(conn, :details, dataset.slug))
    |> html_response(200)
    |> Floki.parse_document!()
    |> Floki.find(~s|div[data-section="dataset-header-links"] a|)
  end

  defp dataset_has_banner_with_text(%Plug.Conn{} = conn, %DB.Dataset{slug: slug}, text) do
    mock_empty_history_resources()

    content =
      conn
      |> get(dataset_path(conn, :details, slug))
      |> html_response(200)
      |> Floki.parse_document!()
      |> Floki.find(".notification")
      |> Floki.text()

    assert content =~ text
  end

  defp extract_resource_details(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("section#dataset-resources div.ressources-list div.resource")
    |> Floki.text()
  end
end
