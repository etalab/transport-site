defmodule TransportWeb.EspaceProducteurControllerTest do
  use Oban.Testing, repo: DB.Repo
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Phoenix.LiveViewTest
  import Plug.Test, only: [init_test_session: 2]
  import Mox

  @gtfs_path "#{__DIR__}/../../fixture/files/gtfs.zip"

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "GET /espace_producteur" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> get(espace_producteur_path(conn, :espace_producteur))
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
      assert redirected_to(conn, 302) == page_path(conn, :infos_producteurs)
    end

    test "renders successfully and finds datasets using organization IDs", %{conn: conn} do
      dataset = insert(:dataset, custom_title: custom_title = "Foobar")

      resource = insert(:resource, url: "https://static.data.gouv.fr/file", dataset: dataset)
      assert DB.Resource.hosted_on_datagouv?(resource)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      last_year = Date.utc_today().year - 1

      insert(:dataset_monthly_metric,
        dataset_datagouv_id: dataset.datagouv_id,
        year_month: "#{last_year}-12",
        metric_name: :downloads,
        count: 120_250
      )

      assert dataset |> DB.Repo.preload(:resources) |> TransportWeb.EspaceProducteurView.show_downloads_stats?()

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :espace_producteur))

      # `is_producer` attribute has been set for the current user
      assert %{"is_producer" => true} = conn |> get_session(:current_user)

      {:ok, doc} = conn |> html_response(200) |> Floki.parse_document()
      assert Floki.find(doc, ".message--error") == []

      assert doc |> Floki.find("h3.dataset__title") |> Enum.map(&(&1 |> Floki.text() |> String.trim())) == [
               custom_title
             ]
    end

    test "action items", %{conn: conn} do
      menu_items = fn %Plug.Conn{} = conn ->
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :espace_producteur))
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find(".publish-header h4")
        |> Floki.text(sep: "|")
        |> String.replace(~r/(\s)+/, " ")
        |> String.split("|")
        |> Enum.map(&String.trim/1)
      end

      %DB.Dataset{organization_id: organization_id} = dataset = insert(:dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, 3, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset, 3)

      assert menu_items.(conn) == [
               "Tester vos jeux de données",
               "Publier un jeu de données",
               "Recevoir des notifications",
               "Discussions sans réponse"
             ]

      # Should show download stats
      resource = insert(:resource, url: "https://static.data.gouv.fr/file", dataset: dataset)
      assert DB.Resource.hosted_on_datagouv?(resource)

      assert menu_items.(conn) == [
               "Tester vos jeux de données",
               "Publier un jeu de données",
               "Recevoir des notifications",
               "Vos statistiques de téléchargements",
               "Discussions sans réponse"
             ]

      # Should show proxy stats
      resource = insert(:resource, url: "https://proxy.transport.data.gouv.fr/url", dataset: dataset)
      assert DB.Resource.served_by_proxy?(resource)

      assert menu_items.(conn) == [
               "Tester vos jeux de données",
               "Publier un jeu de données",
               "Recevoir des notifications",
               "Vos statistiques proxy",
               "Vos statistiques de téléchargements",
               "Discussions sans réponse"
             ]
    end

    test "when user is not a producer", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      conn
      |> init_test_session(%{"is_producer" => false, "current_user" => %{"id" => contact.datagouv_user_id}})
      |> get(espace_producteur_path(conn, :espace_producteur))
      |> html_response(200)
    end

    test "with an OAuth2 error", %{conn: conn} do
      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:error, "its broken"} end)

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :espace_producteur))

      {:ok, doc} = conn |> html_response(200) |> Floki.parse_document()
      assert doc |> Floki.find(".dataset-item") |> length == 0

      assert doc |> Floki.find(".message--error") |> Floki.text() ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "urgent issues panel", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)
      resource = insert(:resource, title: "GTFS Super", format: "GTFS", is_available: false, dataset: dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      Datagouvfr.Client.Organization.Mock
      |> expect(:get, fn ^organization_id, [restrict_fields: true] ->
        {:ok, %{"members" => []}}
      end)

      discussion = %{
        "closed" => nil,
        "discussion" => [
          %{"posted_on" => DateTime.utc_now() |> DateTime.to_iso8601(), "posted_by" => %{"id" => Ecto.UUID.generate()}}
        ],
        "id" => discussion_id = Ecto.UUID.generate()
      }

      Datagouvfr.Client.Discussions.Mock |> expect(:get, fn ^datagouv_id -> [discussion] end)

      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :espace_producteur))
        |> html_response(200)
        |> Floki.parse_document!()

      # Filter out recent_features row if present (during first 7 days of month)
      all_tbody_rows = doc |> Floki.find(~s|[data-name="urgent-issues"] tbody tr|)

      tbody_rows_without_recent_features =
        all_tbody_rows
        |> Enum.reject(fn row ->
          row |> Floki.text() |> String.contains?("Nouvelles fonctionnalités")
        end)

      # Expected tbody structure without recent_features
      expected_tbody_rows = [
        {"tr", [],
         [
           {"td", [],
            [
              {"a", [{"href", dataset_path(conn, :details, dataset.slug)}, {"target", "_blank"}],
               [{"i", [{"class", "fa fa-external-link"}], []}, "\n      Hello\n    "]}
            ]},
           {"td", [], []},
           {"td", [], ["Discussions sans réponse"]},
           {"td", [],
            [
              {"a",
               [
                 {"href", dataset_path(conn, :details, dataset.slug) <> "#discussion-" <> discussion_id},
                 {"class", "button-outline primary small"},
                 {"data-tracking-category", "espace_producteur"},
                 {"data-tracking-action", "urgent_issues_see_discussion_button"}
               ],
               [
                 {"i", [{"class", "icon fas fa-comments"}], []},
                 "Voir la discussion\n  "
               ]}
            ]}
         ]},
        {"tr", [],
         [
           {"td", [],
            [
              {"a", [{"href", dataset_path(conn, :details, dataset.slug)}, {"target", "_blank"}],
               [{"i", [{"class", "fa fa-external-link"}], []}, "\n      Hello\n    "]}
            ]},
           {"td", [], ["GTFS Super ", {"span", [{"class", "label"}], ["GTFS"]}]},
           {"td", [], ["Ressource indisponible"]},
           {"td", [],
            [
              {"a",
               [
                 {"href", espace_producteur_path(conn, :edit_resource, dataset.id, resource.datagouv_id)},
                 {"class", "button-outline primary small"},
                 {"data-tracking-category", "espace_producteur"},
                 {"data-tracking-action", "urgent_issues_edit_resource_button"}
               ],
               [
                 {"i", [{"class", "fa fa-edit"}], []},
                 "Modifier la ressource\n  "
               ]}
            ]}
         ]}
      ]

      assert tbody_rows_without_recent_features == expected_tbody_rows

      # Verify the complete structure with the filtered tbody
      assert doc |> Floki.find(~s|[data-name="urgent-issues"]|) |> length() == 1

      assert doc |> Floki.find(~s|[data-name="urgent-issues"] h2|) |> Floki.text() ==
               "Problèmes urgents sur vos ressources"

      assert doc
             |> Floki.find(~s|[data-name="urgent-issues"] p|)
             |> Floki.text() ==
               "Les problèmes sur les ressources suivantes requièrent votre attention."

      # Verify table structure
      assert doc |> Floki.find(~s|[data-name="urgent-issues"] table|) |> length() == 1

      # If we're in the first 7 days, recent_features row should be present
      if Date.utc_today().day in 1..7 do
        assert length(all_tbody_rows) == 3

        assert Enum.any?(all_tbody_rows, fn row ->
                 row |> Floki.text() |> String.contains?("Nouvelles fonctionnalités")
               end)
      else
        assert length(all_tbody_rows) == 2
      end
    end
  end

  test "urgent_issues for expiring_resource" do
    %{resource: resource, dataset: dataset, multi_validation: multi_validation} =
      insert_resource_and_friends(Date.utc_today())

    multi_validation = multi_validation |> DB.Repo.preload(:metadata)

    start_date =
      DB.MultiValidation.get_metadata_info(multi_validation, "start_date") |> Shared.DateTimeDisplay.format_date("fr")

    end_date =
      DB.MultiValidation.get_metadata_info(multi_validation, "end_date") |> Shared.DateTimeDisplay.format_date("fr")

    assert render_component(&TransportWeb.EspaceProducteurView.urgent_issue/1,
             issue: resource,
             dataset: dataset,
             check_name: :expiring_resource,
             multi_validation: multi_validation,
             locale: "fr",
             mode: :producer
           )
           |> Floki.parse_document!() == [
             {"tr", [],
              [
                {"td", [],
                 [
                   {"a", [{"href", dataset_path(TransportWeb.Endpoint, :details, dataset.slug)}, {"target", "_blank"}],
                    [{"i", [{"class", "fa fa-external-link"}], []}, "\n      Hello\n    "]}
                 ]},
                {"td", [],
                 [
                   "GTFS.zip ",
                   {"span", [{"class", "label"}], ["GTFS"]},
                   {"div", [{"title", "Période de validité"}],
                    [
                      {"i", [{"class", "icon icon--calendar-alt"}, {"aria-hidden", "true"}], []},
                      {"span", [], [start_date]},
                      {"i",
                       [
                         {"class", "icon icon--right-arrow ml-05-em"},
                         {"aria-hidden", "true"}
                       ], []},
                      {"span", [{"class", "resource__summary--Error"}], [end_date]}
                    ]}
                 ]},
                {"td", [], ["Ressource expirée"]},
                {"td", [],
                 [
                   {"a",
                    [
                      {"href",
                       espace_producteur_path(TransportWeb.Endpoint, :edit_resource, dataset.id, resource.datagouv_id)},
                      {"class", "button-outline primary small"},
                      {"data-tracking-category", "espace_producteur"},
                      {"data-tracking-action", "urgent_issues_edit_resource_button"}
                    ], [{"i", [{"class", "fa fa-edit"}], []}, "Modifier la ressource\n  "]}
                 ]}
              ]}
           ]
  end

  describe "edit_dataset" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :edit_dataset, 42)) |> assert_redirects_to_info_page()
    end

    test "redirects if you're not a member of the dataset organization", %{conn: conn} do
      dataset = insert(:dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => []}} end)

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "renders successfully and finds the dataset using organization IDs", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: dataset_datagouv_id} = dataset = insert(:dataset)

      %DB.Resource{datagouv_id: resource_datagouv_id} = resource = insert(:resource, dataset: dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, 2, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 2, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_id: resource_datagouv_id)
      end)

      mock_organization_and_discussion(dataset, 2)

      td_text = fn doc ->
        doc |> Floki.find("td.align-right") |> Floki.text() |> String.replace(~r/(\s)+/, " ") |> String.trim()
      end

      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert td_text.(doc) == "Modifier la ressource Supprimer la ressource"

      # With a reuser improved data
      insert(:reuser_improved_data, dataset: dataset, resource: resource)

      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert td_text.(doc) == "Modifier la ressource GTFS réutilisateurSupprimer la ressource"
    end

    test "when a custom logo is set", %{conn: conn} do
      %DB.Dataset{
        id: dataset_id,
        datagouv_id: datagouv_id,
        organization_id: organization_id
      } = dataset = insert(:dataset, custom_logo: "https://example.com/pic.png")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id -> {:ok, generate_dataset_payload(datagouv_id)} end)

      content =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset_id))
        |> html_response(200)

      assert content
             |> Floki.parse_document!()
             |> Floki.find(~s{.producer-actions button[type="submit"]})
             |> Floki.text() =~ "Supprimer le logo personnalisé"
    end

    test "validity dates, validity and urgent issues for a GTFS", %{conn: conn} do
      %DB.Dataset{
        id: dataset_id,
        datagouv_id: datagouv_id,
        organization_id: organization_id
      } = dataset = insert(:dataset)

      %{resource: %DB.Resource{} = resource} = insert_resource_and_friends(~D[2025-12-25], dataset: dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id ->
        dataset_datagouv_get_response(datagouv_id, resource_id: resource.datagouv_id)
      end)

      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset_id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert doc |> Floki.find(~s|[data-name="validity-dates"]|) == [
               {"td", [{"data-name", "validity-dates"}],
                [
                  {"div", [{"title", "Période de validité"}],
                   [
                     {"i", [{"class", "icon icon--calendar-alt"}, {"aria-hidden", "true"}], []},
                     {"span", [], ["26/10/2025"]},
                     {"i", [{"class", "icon icon--right-arrow ml-05-em"}, {"aria-hidden", "true"}], []},
                     {"span", [{"class", "resource__summary--Error"}], ["25/12/2025"]}
                   ]}
                ]}
             ]

      assert doc |> Floki.find(~s|[data-name="validity"]|) == [
               {"td", [{"data-name", "validity"}, {"class", "no-underline"}],
                [
                  {"div", [{"class", "pb-24"}],
                   [
                     {"a", [{"href", resource_path(conn, :details, resource.id) <> "#validation-report"}],
                      [{"span", [{"class", "resource__summary--Success"}], ["\n\n          Pas d'erreur\n\n      "]}]},
                     {"span", [], ["lors de la validation"]}
                   ]}
                ]}
             ]

      assert doc |> Floki.find(~s|[data-name="urgent-issues"] h2|) |> Floki.text() ==
               "Problèmes urgents sur vos ressources"
    end

    test "validity for a TableSchema", %{conn: conn} do
      %DB.Dataset{
        id: dataset_id,
        datagouv_id: datagouv_id,
        organization_id: organization_id
      } = dataset = insert(:dataset)

      resource = insert(:resource, dataset: dataset)

      schema_name = "etalab/foo"

      result = %{"has_errors" => true, "errors_count" => 1, "validation_performed" => true, "errors" => ["oops"]}

      insert(:multi_validation,
        resource_history: insert(:resource_history, resource_id: resource.id, payload: %{"schema_name" => schema_name}),
        validator: Transport.Validators.TableSchema.validator_name(),
        result: result,
        digest: Transport.Validators.TableSchema.digest(result)
      )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id ->
        dataset_datagouv_get_response(datagouv_id, resource_id: resource.datagouv_id)
      end)

      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset_id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert doc |> Floki.find(~s|[data-name="validity-dates"|) == [{"td", [{"data-name", "validity-dates"}], []}]

      assert doc |> Floki.find(~s|[data-name="validity"|) == [
               {"td", [{"data-name", "validity"}, {"class", "no-underline"}],
                [
                  {"div", [{"class", "pb-24"}],
                   [
                     {"a",
                      [
                        {"href", resource_path(conn, :details, resource.id) <> "#validation-report"}
                      ],
                      [{"span", [{"class", "resource__summary--Error"}], ["\n\n\n\n            1 erreur\n\n        "]}]},
                     {"span", [], ["lors de la validation"]}
                   ]}
                ]}
             ]
    end

    test "when another dataset has failing dataset checks", %{conn: conn} do
      %DB.Dataset{
        id: dataset_id,
        datagouv_id: datagouv_id,
        organization_id: organization_id
      } = dataset = insert(:dataset)

      resource = insert(:resource, dataset: dataset)

      %DB.Dataset{datagouv_id: d2_datagouvid} = d2 = insert(:dataset, organization_id: organization_id)
      insert(:resource, dataset: d2, is_available: false)

      Datagouvfr.Client.User.Mock
      |> expect(:me, 2, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)
      mock_organization_and_discussion(d2)

      mock_organization_and_discussion(dataset)
      mock_organization_and_discussion(d2)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id ->
        dataset_datagouv_get_response(datagouv_id, resource_id: resource.datagouv_id)
      end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^d2_datagouvid ->
        dataset_datagouv_get_response(d2_datagouvid, resource_id: resource.datagouv_id)
      end)

      # Panel is not displayed
      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, dataset_id))
        |> html_response(200)
        |> Floki.parse_document!()

      # urgent-issues may be present if we're in first 7 days (recent_features banner)
      # but should not contain any real issues (only recent_features if present)
      urgent_issues_rows = doc |> Floki.find(~s|[data-name="urgent-issues"] tbody tr|)

      real_issues_rows =
        urgent_issues_rows
        |> Enum.reject(fn row ->
          row |> Floki.text() |> String.contains?("Nouvelles fonctionnalités")
        end)

      assert Enum.empty?(real_issues_rows)

      # Other dataset has the panel displayed
      doc =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_dataset, d2.id))
        |> html_response(200)
        |> Floki.parse_document!()

      refute doc |> Floki.find(~s|[data-name="urgent-issues"]|) |> Enum.empty?()
    end
  end

  describe "upload_logo" do
    test "requires authentication", %{conn: conn} do
      conn
      |> post(espace_producteur_path(conn, :upload_logo, 42), %{"upload" => %{"file" => %Plug.Upload{}}})
      |> assert_redirects_to_info_page()
    end

    test "redirects if you're not a member of the dataset organization", %{conn: conn} do
      dataset = insert(:dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => []}} end)

      conn =
        conn
        |> init_session_for_producer()
        |> post(espace_producteur_path(conn, :upload_logo, dataset.id), %{"upload" => %{"file" => %Plug.Upload{}}})

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "uploads the logo to S3, enqueue a job and redirect", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)

      filename = "sample.jpg"
      local_path = System.tmp_dir!() |> Path.join(filename)
      upload_path = "tmp_#{datagouv_id}.jpg"

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Transport.ExAWS.Mock
      |> expect(:request!, fn %ExAws.S3.Upload{
                                src: %File.Stream{path: ^local_path},
                                bucket: "transport-data-gouv-fr-logos-test",
                                path: ^upload_path,
                                opts: [acl: :private],
                                service: :s3
                              } ->
        :ok
      end)

      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      conn =
        conn
        |> init_test_session(current_user: %{"id" => contact.datagouv_user_id, "is_producer" => true})
        |> post(espace_producteur_path(conn, :upload_logo, dataset.id), %{
          "upload" => %{"file" => %Plug.Upload{path: local_path, filename: filename}}
        })

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.CustomLogoConversionJob",
                 args: %{"datagouv_id" => ^datagouv_id, "path" => ^upload_path}
               }
             ] = all_enqueued()

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert [
               %DB.FeatureUsage{
                 feature: :upload_logo,
                 contact_id: ^contact_id,
                 metadata: %{
                   "dataset_datagouv_id" => ^datagouv_id
                 }
               }
             ] = DB.Repo.all(DB.FeatureUsage)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Votre logo a bien été reçu. Il sera remplacé dans quelques instants."
    end
  end

  describe "remove_custom_logo" do
    test "requires authentication", %{conn: conn} do
      conn |> delete(espace_producteur_path(conn, :remove_custom_logo, 42)) |> assert_redirects_to_info_page()
    end

    test "redirects if you're not a member of the dataset organization", %{conn: conn} do
      dataset = insert(:dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => []}} end)

      conn =
        conn
        |> init_session_for_producer()
        |> delete(espace_producteur_path(conn, :remove_custom_logo, dataset.id))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "deletes objects and resets custom logos", %{conn: conn} do
      custom_logo_path = "#{Ecto.UUID.generate()}.png"
      custom_full_logo_path = "#{Ecto.UUID.generate()}_full.png"
      bucket_url = Transport.S3.permanent_url(:logos)

      dataset =
        insert(:dataset,
          custom_logo: Path.join(bucket_url, custom_logo_path),
          custom_full_logo: Path.join(bucket_url, custom_full_logo_path)
        )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Transport.Test.S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:logos), custom_logo_path)
      Transport.Test.S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:logos), custom_full_logo_path)

      conn =
        conn
        |> init_session_for_producer()
        |> delete(espace_producteur_path(conn, :remove_custom_logo, dataset.id))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Votre logo personnalisé a été supprimé."

      assert %DB.Dataset{custom_logo: nil, custom_full_logo: nil, custom_logo_changed_at: custom_logo_changed_at} =
               DB.Repo.reload!(dataset)

      assert DateTime.diff(custom_logo_changed_at, DateTime.utc_now(), :second) < 3
    end
  end

  describe "proxy_statistics" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :proxy_statistics)) |> assert_redirects_to_info_page()
    end

    test "redirects when there is an error when fetching datasets", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> {:error, nil} end)

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :proxy_statistics))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "renders successfully with a resource handled by the proxy", %{conn: conn} do
      dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

      gtfs_rt_resource =
        insert(:resource,
          dataset: dataset,
          format: "gtfs-rt",
          url: "https://proxy.transport.data.gouv.fr/resource/divia-dijon-gtfs-rt-trip-update"
        )

      assert DB.Resource.served_by_proxy?(gtfs_rt_resource)
      proxy_slug = DB.Resource.proxy_slug(gtfs_rt_resource)
      assert proxy_slug == "divia-dijon-gtfs-rt-trip-update"

      today = Transport.Telemetry.truncate_datetime_to_hour(DateTime.utc_now())

      insert(:metrics,
        target: "proxy:#{proxy_slug}",
        event: "proxy:request:external",
        count: 2,
        period: today
      )

      insert(:metrics,
        target: "proxy:#{proxy_slug}",
        event: "proxy:request:internal",
        count: 1,
        period: today
      )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      html =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :proxy_statistics))
        |> html_response(200)

      assert_breadcrumb_content(html, ["Votre espace producteur", "Statistiques du proxy Transport"])

      assert html =~ "Statistiques des requêtes gérées par le proxy"
      assert html =~ "<strong>\n      2\n    </strong>\n    requêtes gérées par le proxy au cours des 15 derniers jours"

      assert html =~
               "<strong>\n      1\n    </strong>\n    requêtes transmises au serveur source au cours des 15 derniers jours"
    end
  end

  describe "download_statistics_csv" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :download_statistics_csv)) |> assert_redirects_to_info_page()
    end

    test "redirects when there is an error when fetching datasets", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> {:error, nil} end)

      conn = conn |> init_session_for_producer() |> get(espace_producteur_path(conn, :download_statistics_csv))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "renders successfully with a datagouv resource", %{conn: conn} do
      dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/url", title: "GTFS.zip")

      assert DB.Resource.hosted_on_datagouv?(resource)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      insert(:resource_monthly_metric,
        metric_name: :downloads,
        dataset_datagouv_id: dataset.datagouv_id,
        resource_datagouv_id: resource.datagouv_id,
        count: 2,
        year_month: "2025-12"
      )

      assert [dataset |> DB.Repo.preload(:resources)] |> DB.ResourceMonthlyMetric.download_statistics() == [
               %{
                 count: 2,
                 dataset_title: dataset.custom_title,
                 resource_title: resource.title,
                 year_month: "2025-12",
                 dataset_datagouv_id: dataset.datagouv_id,
                 resource_datagouv_id: resource.datagouv_id
               }
             ]

      response =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :download_statistics_csv))

      assert response_content_type(response, :csv) == "text/csv; charset=utf-8"

      assert Plug.Conn.get_resp_header(response, "content-disposition") == [
               ~s(attachment; filename="download_statistics-#{Date.utc_today() |> Date.to_iso8601()}.csv")
             ]

      assert [response(response, 200)] |> CSV.decode!(headers: true) |> Enum.to_list() == [
               %{
                 "count" => "2",
                 "dataset_datagouv_id" => dataset.datagouv_id,
                 "dataset_title" => dataset.custom_title,
                 "resource_datagouv_id" => resource.datagouv_id,
                 "resource_title" => "GTFS.zip",
                 "year_month" => "2025-12"
               }
             ]
    end
  end

  describe "proxy_statistics_csv" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :proxy_statistics_csv)) |> assert_redirects_to_info_page()
    end

    test "redirects when there is an error when fetching datasets", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> {:error, nil} end)

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :proxy_statistics_csv))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "renders successfully with a resource handled by the proxy", %{conn: conn} do
      dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

      slug = "divia-dijon-gtfs-rt-trip-update"

      gtfs_rt_resource =
        insert(:resource,
          dataset: dataset,
          format: "gtfs-rt",
          url: "https://proxy.transport.data.gouv.fr/resource/#{slug}"
        )

      assert DB.Resource.served_by_proxy?(gtfs_rt_resource)
      proxy_slug = DB.Resource.proxy_slug(gtfs_rt_resource)
      assert proxy_slug == slug

      insert(:metrics,
        target: "proxy:#{proxy_slug}",
        event: "proxy:request:external",
        count: 2,
        period: ~U[2025-11-01 10:00:00.0Z]
      )

      insert(:metrics,
        target: "proxy:#{proxy_slug}",
        event: "proxy:request:internal",
        count: 1,
        period: ~U[2025-11-01 10:00:00.0Z]
      )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      response =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :proxy_statistics_csv))

      assert response_content_type(response, :csv) == "text/csv; charset=utf-8"

      assert Plug.Conn.get_resp_header(response, "content-disposition") == [
               ~s(attachment; filename="proxy_statistics-#{Date.utc_today() |> Date.to_iso8601()}.csv")
             ]

      assert [response(response, 200)] |> CSV.decode!(headers: true) |> Enum.to_list() == [
               %{
                 "count" => "2",
                 "event" => "proxy:request:external",
                 "month" => "2025-11",
                 "target" => "proxy:divia-dijon-gtfs-rt-trip-update"
               },
               %{
                 "count" => "1",
                 "event" => "proxy:request:internal",
                 "month" => "2025-11",
                 "target" => "proxy:divia-dijon-gtfs-rt-trip-update"
               }
             ]
    end
  end

  describe "resource_actions" do
    test "we can show the form of an existing remote resource", %{conn: conn} do
      conn = conn |> init_session_for_producer()

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        dataset =
        insert(:dataset, custom_title: custom_title = "Base Nationale des Lieux de Covoiturage")

      resource = insert(:resource, url: url = "https://example.com/file", dataset: dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_id: resource.datagouv_id)
      end)

      html =
        conn
        |> get(espace_producteur_path(conn, :edit_resource, dataset_id, resource.datagouv_id))
        |> html_response(200)

      doc = html |> Floki.parse_document!()
      assert_breadcrumb_content(html, ["Votre espace producteur", custom_title, "Modifier une ressource"])

      # Title
      assert doc |> Floki.find("h2") |> Floki.text(sep: "|") == "Modification d’une ressource|Laissez-nous votre avis"
      assert html =~ "bnlc.csv"
      assert html =~ url
    end

    test "edit a resource for a GTFS file", %{conn: conn} do
      resource_datagouv_id = Ecto.UUID.generate()

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        dataset = insert(:dataset)

      insert(:resource, format: "GTFS", datagouv_id: resource_datagouv_id, dataset_id: dataset_id)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_id: resource_datagouv_id, filetype: "file")
      end)

      html =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :edit_resource, dataset_id, resource_datagouv_id))
        |> html_response(200)
        |> Floki.parse_document!()

      refute html |> Floki.find("form#upload-form") |> is_nil()
    end

    test "we can show the form for a new resource", %{conn: conn} do
      conn = conn |> init_session_for_producer()

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        dataset =
        insert(:dataset, custom_title: custom_title = "Base Nationale des Lieux de Covoiturage")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id -> dataset_datagouv_get_response(dataset_datagouv_id) end)

      doc =
        conn
        |> get(espace_producteur_path(conn, :new_resource, dataset_id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert_breadcrumb_content(doc, ["Votre espace producteur", custom_title, "Nouvelle ressource"])
      # Title
      assert doc |> Floki.find("h2") |> Floki.text(sep: "|") == "Ajouter une nouvelle ressource|Laissez-nous votre avis"
    end

    test "we can add a new resource with a URL", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> [] end)
      %DB.Dataset{datagouv_id: dataset_datagouv_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      conn = conn |> init_test_session(%{current_user: %{"id" => contact.datagouv_user_id, "is_producer" => true}})

      # We expect a call to the function Datagouvfr.Client.Resource.update/2, but this is indeed to create a new resource.
      # There is a clause in the real client that does a POST call for a new resource if there is no resource_id
      Datagouvfr.Client.Resources.Mock
      |> expect(:update, fn _conn,
                            %{
                              "dataset_id" => ^dataset_datagouv_id,
                              "format" => "csv",
                              "title" => "Test",
                              "url" => "https://example.com/my_csv_resource.csv"
                            } = _params ->
        # We don’t really care about API answer, as it is discarded and not used (see controller code)
        {:ok, %{}}
      end)

      # We need to mock other things too:
      # Adding a new resource triggers an ImportData, and then a validation.
      mocks_for_import_data_etc(dataset_datagouv_id)

      location =
        conn
        |> post(
          espace_producteur_path(conn, :post_file, dataset_datagouv_id),
          %{
            "form" => %{
              "format" => "csv",
              "title" => "Test",
              "url" => "https://example.com/my_csv_resource.csv"
            }
          }
        )
        |> redirected_to

      assert location == dataset_path(conn, :details, dataset_datagouv_id)
      # No need to really check content of dataset and resources in database,
      # because the response of Datagouv.Client.Resources.update is discarded.
      # We would just check that import_data works correctly, while this is already tested elsewhere.
      assert [
               %DB.FeatureUsage{
                 feature: :upload_file,
                 contact_id: ^contact_id,
                 metadata: %{
                   "dataset_datagouv_id" => ^dataset_datagouv_id,
                   "format" => "csv"
                 }
               }
             ] = DB.Repo.all(DB.FeatureUsage)
    end

    test "post_file with a file with hidden fields", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> [] end)
      %DB.Dataset{datagouv_id: dataset_datagouv_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      conn = conn |> init_test_session(%{current_user: %{"id" => contact.datagouv_user_id, "is_producer" => true}})

      Datagouvfr.Client.Resources.Mock
      |> expect(:update, fn %Plug.Conn{},
                            %{
                              "dataset_id" => ^dataset_datagouv_id,
                              "format" => "GTFS",
                              "title" => "Test",
                              "resource_file" => %Plug.Upload{
                                path: @gtfs_path,
                                filename: "GTFS.zip"
                              }
                            } = _params ->
        # We don’t really care about API answer, as it is discarded and not used (see controller code)
        {:ok, %{}}
      end)

      mocks_for_import_data_etc(dataset_datagouv_id)

      assert conn
             |> post(
               espace_producteur_path(conn, :post_file, dataset_datagouv_id),
               %{
                 "format" => "GTFS",
                 "title" => "Test",
                 "resource_file" => %{
                   "filename" => "GTFS.zip",
                   "path" => @gtfs_path
                 }
               }
             )
             |> redirected_to(302) == dataset_path(conn, :details, dataset_datagouv_id)

      assert [
               %DB.FeatureUsage{
                 feature: :upload_file,
                 contact_id: ^contact_id,
                 metadata: %{
                   "dataset_datagouv_id" => ^dataset_datagouv_id,
                   "format" => "GTFS"
                 }
               }
             ] = DB.Repo.all(DB.FeatureUsage)
    end

    test "we can show the delete confirmation page", %{conn: conn} do
      conn = conn |> init_session_for_producer()
      resource_datagouv_id = "resource_dataset_id"

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        dataset =
        insert(:dataset, custom_title: custom_title = "Base Nationale des Lieux de Covoiturage")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_id: resource_datagouv_id)
      end)

      html =
        conn
        |> get(espace_producteur_path(conn, :delete_resource_confirmation, dataset_id, resource_datagouv_id))
        |> html_response(200)

      assert_breadcrumb_content(html, ["Votre espace producteur", custom_title, "Supprimer une ressource"])

      assert html =~ "bnlc.csv"
      assert html =~ "Souhaitez-vous mettre à jour la ressource ou la supprimer définitivement ?"
    end

    test "we can delete a resource", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> [] end)

      %DB.Dataset{datagouv_id: dataset_datagouv_id, resources: [%DB.Resource{datagouv_id: resource_datagouv_id}]} =
        insert(:dataset, resources: [insert(:resource)])

      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      conn = conn |> init_test_session(%{current_user: %{"id" => contact.datagouv_user_id, "is_producer" => true}})

      Datagouvfr.Client.Resources.Mock
      |> expect(:delete, fn _conn, %{"dataset_id" => ^dataset_datagouv_id, "resource_id" => ^resource_datagouv_id} ->
        # We don’t really care about API answer, as it is discarded and not used (see controller code)
        {:ok, %{}}
      end)

      # We need to mock other things too:
      # Adding a new resource triggers an ImportData, and then a validation.
      mocks_for_import_data_etc(dataset_datagouv_id)

      location =
        conn
        |> delete(espace_producteur_path(conn, :delete_resource, dataset_datagouv_id, resource_datagouv_id))
        |> redirected_to

      assert location == espace_producteur_path(conn, :espace_producteur)
      # No need to really check content of dataset and resources in database,
      # because the response of Datagouv.Client.Resources.update is discarded.
      # We would just check that import_data works correctly, while this is already tested elsewhere.

      assert [
               %DB.FeatureUsage{
                 feature: :delete_resource,
                 contact_id: ^contact_id,
                 metadata: %{
                   "dataset_datagouv_id" => ^dataset_datagouv_id,
                   "resource_datagouv_id" => ^resource_datagouv_id
                 }
               }
             ] = DB.Repo.all(DB.FeatureUsage)
    end
  end

  describe "reuser_improved_data" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :reuser_improved_data, 42, 1337)) |> assert_redirects_to_info_page()
    end

    test "redirects if you're not a member of the dataset organization", %{conn: conn} do
      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => []}} end)

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :reuser_improved_data, 42, 1337))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "we can see reuser improved data", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset)

      reuser_improved_data =
        insert(:reuser_improved_data, dataset: dataset, resource: resource) |> DB.Repo.preload([:organization])

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id -> {:ok, generate_dataset_payload(datagouv_id)} end)

      html =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :reuser_improved_data, dataset.id, resource.id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert_breadcrumb_content(html, ["Votre espace producteur", dataset.custom_title, resource.title])

      assert html |> Floki.find("h2") |> Floki.text() =~ "Repartage des données améliorées"
      assert html |> Floki.find("table") |> Floki.text() =~ reuser_improved_data.organization.name

      # Actions buttons
      download_url = reuser_improved_data.download_url

      assert [
               {"a",
                [
                  {"class", "button-outline reuser small"},
                  {"data-tracking-action", "download_reuser_gtfs"},
                  {"data-tracking-category", "espace_producteur"},
                  {"href", ^download_url},
                  {"target", "_blank"}
                ], ["Télécharger le GTFS réutilisateur"]},
               {"a",
                [
                  {"class", "button-outline primary small"},
                  {"data-tracking-action", "see_gtfs_diff_report"},
                  {"data-tracking-category", "espace_producteur"},
                  {"href", gtfs_diff_url},
                  {"target", "_blank"}
                ], ["Comparer avec mon GTFS"]}
             ] = html |> Floki.find("a.button-outline")

      %URI{path: "/tools/gtfs_diff", query: query} = URI.new!(gtfs_diff_url)

      assert %{"modified_url" => reuser_improved_data.download_url, "reference_url" => resource.url} ==
               URI.decode_query(query)
    end
  end

  describe "download_statistics" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :download_statistics)) |> assert_redirects_to_info_page()
    end

    test "redirects when there is an error when fetching datasets", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> {:error, nil} end)

      conn =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :download_statistics))

      assert redirected_to(conn, 302) == espace_producteur_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "renders successfully", %{conn: conn} do
      %DB.Dataset{} = dataset = insert(:dataset)

      resource =
        insert(:resource,
          title: "gtfs.zip",
          format: "GTFS",
          url: "https://static.data.gouv.fr/example.zip",
          dataset: dataset
        )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      mock_organization_and_discussion(dataset)

      current_year = Date.utc_today().year
      previous_year = current_year - 1
      year_month = Date.utc_today() |> Date.to_iso8601() |> String.slice(0..6)
      previous_year_month = "#{previous_year}-01"

      insert(:resource_monthly_metric,
        resource_datagouv_id: resource.datagouv_id,
        metric_name: :downloads,
        count: 2_000,
        year_month: year_month
      )

      insert(:resource_monthly_metric,
        resource_datagouv_id: resource.datagouv_id,
        metric_name: :downloads,
        count: 1_500,
        year_month: previous_year_month
      )

      html =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :download_statistics))
        |> html_response(200)

      assert_breadcrumb_content(html, ["Votre espace producteur", "Statistiques de téléchargements"])

      assert html =~ "<h2>Statistiques de téléchargements</h2>"

      assert html |> Floki.parse_document!() |> Floki.find("table") == [
               {"table", [{"class", "table small-padding"}],
                [
                  {"thead", [],
                   [
                     {"tr", [],
                      [
                        {"th", [], ["Jeu de données"]},
                        {"th", [], ["Ressource"]},
                        {"th", [], ["Téléchargements de l'année #{previous_year}"]},
                        {"th", [], ["Téléchargements de l'année #{current_year}"]}
                      ]}
                   ]},
                  {"tbody", [],
                   [
                     {"tr", [],
                      [
                        {"td", [{"rowspan", "1"}], [dataset.custom_title]},
                        {"td", [], [resource.title <> " ", {"span", [{"class", "label"}], [resource.format]}]},
                        {"td", [], ["\n1 500\n                "]},
                        {"td", [], ["\n2 000\n                "]}
                      ]}
                   ]}
                ]}
             ]
    end
  end

  describe "discussions" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :discussions)) |> assert_redirects_to_info_page()
    end

    test "we can see unanswered discussions", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      Datagouvfr.Client.Organization.Mock
      |> expect(:get, 2, fn ^organization_id, [restrict_fields: true] ->
        {:ok, %{"members" => []}}
      end)

      discussion = %{
        "id" => Ecto.UUID.generate(),
        "closed" => nil,
        "title" => "Discussion title",
        "discussion" => [
          %{
            "posted_on" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "posted_by" => %{"id" => Ecto.UUID.generate()}
          }
        ]
      }

      Datagouvfr.Client.Discussions.Mock
      |> expect(:get, 2, fn ^datagouv_id -> [discussion] end)

      html =
        conn
        |> init_session_for_producer()
        |> get(espace_producteur_path(conn, :discussions))
        |> html_response(200)

      doc = html |> Floki.parse_document!()

      assert doc |> Floki.find("table") == [
               {"table", [{"class", "table small-padding"}],
                [
                  {"thead", [],
                   [{"tr", [], [{"th", [], ["Jeu de données"]}, {"th", [], ["Discussion"]}, {"th", [], ["Lien"]}]}]},
                  {"tbody", [],
                   [
                     {"tr", [],
                      [
                        {"td", [{"rowspan", "1"}],
                         [
                           {"a", [{"href", dataset_path(conn, :details, dataset.slug)}, {"target", "_blank"}],
                            [
                              {"i", [{"class", "fa fa-external-link"}], []},
                              "\n                    Hello\n                  "
                            ]}
                         ]},
                        {"td", [], ["Discussion title"]},
                        {"td", [],
                         [
                           {"a",
                            [
                              {"href",
                               dataset_path(conn, :details, dataset.slug) <> ~s|#discussion-#{discussion["id"]}|},
                              {"target", "_blank"},
                              {"class", "button-outline primary small"},
                              {"data-tracking-category", "espace_producteur"},
                              {"data-tracking-action", "unanswered_discussion_button"}
                            ],
                            [
                              {"i", [{"class", "icon fas fa-comments"}], []},
                              "\n                    Voir la discussion\n                  "
                            ]}
                         ]}
                      ]}
                   ]}
                ]}
             ]

      assert doc |> Floki.find(".notification") |> Enum.empty?()

      assert_breadcrumb_content(html, ["Votre espace producteur", "Discussions sans réponse"])
    end
  end

  test "formats_for_dataset" do
    dataset = insert(:dataset, type: "public-transit")
    other_dataset = insert(:dataset, type: "vehicles-sharing")
    insert(:resource, format: "GTFS", dataset: dataset)
    insert(:resource, format: "GTFS", dataset: dataset)
    insert(:resource, format: "NeTEx", dataset: dataset)
    insert(:resource, format: "gbfs", dataset: other_dataset)

    assert ["GTFS", "NeTEx"] ==
             TransportWeb.EspaceProducteurController.formats_for_dataset(%Plug.Conn{assigns: %{dataset: dataset}})

    assert ["gbfs"] ==
             TransportWeb.EspaceProducteurController.formats_for_dataset(%Plug.Conn{assigns: %{dataset: other_dataset}})
  end

  defp assert_redirects_to_info_page(%Plug.Conn{} = conn) do
    Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    assert redirected_to(conn, 302) == page_path(conn, :infos_producteurs)
  end

  defp dataset_datagouv_get_response(dataset_datagouv_id, opts \\ []) do
    {:ok,
     datagouv_dataset_response(%{
       "id" => dataset_datagouv_id,
       "title" => "Base Nationale des Lieux de Covoiturage",
       "resources" =>
         generate_resources_payload(
           title: "bnlc.csv",
           url: "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv",
           id: Keyword.get(opts, :resource_id, "resource_id_1"),
           format: "csv",
           filetype: Keyword.get(opts, :filetype, "remote")
         )
     })}
  end

  test "show_downloads_stats?" do
    dataset = insert(:dataset)
    refute dataset |> DB.Repo.preload(:resources) |> TransportWeb.EspaceProducteurView.show_downloads_stats?()

    resource = insert(:resource, dataset: dataset)
    refute DB.Resource.hosted_on_datagouv?(resource)
    refute dataset |> DB.Repo.preload(:resources) |> TransportWeb.EspaceProducteurView.show_downloads_stats?()

    resource = insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/file.csv")
    assert DB.Resource.hosted_on_datagouv?(resource)
    assert dataset |> DB.Repo.preload(:resources) |> TransportWeb.EspaceProducteurView.show_downloads_stats?()

    # Works with list
    dataset = dataset |> DB.Repo.preload(:resources)
    other_dataset = insert(:dataset) |> DB.Repo.preload(:resources)
    assert [dataset, other_dataset] |> TransportWeb.EspaceProducteurView.show_downloads_stats?()
  end

  defp mocks_for_import_data_etc(dataset_datagouv_id) do
    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      fn _url, [], hackney: [follow_redirect: true] ->
        %HTTPoison.Response{body: Jason.encode!(generate_dataset_payload(dataset_datagouv_id)), status_code: 200}
      end
    )

    Datagouvfr.Client.CommunityResources.Mock |> expect(:get, fn _ -> {:ok, []} end)
    Mox.stub_with(Transport.AvailabilityChecker.Mock, Transport.AvailabilityChecker.Dummy)
  end

  defp assert_breadcrumb_content(html, expected) when is_binary(html) do
    assert_breadcrumb_content(Floki.parse_document!(html), expected)
  end

  defp assert_breadcrumb_content(doc, expected) do
    assert doc |> Floki.find(".breadcrumbs-element") |> Enum.map(&Floki.text/1) == expected
  end

  defp init_session_for_producer(%Plug.Conn{} = conn) do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    conn |> init_test_session(current_user: %{"is_producer" => true, "id" => contact.datagouv_user_id})
  end

  defp mock_organization_and_discussion(
         %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id},
         times \\ 1
       ) do
    Datagouvfr.Client.Organization.Mock
    |> expect(:get, times, fn ^organization_id, [restrict_fields: true] ->
      {:ok, %{"members" => []}}
    end)

    Datagouvfr.Client.Discussions.Mock |> expect(:get, times, fn ^datagouv_id -> [] end)
  end
end
