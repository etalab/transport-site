defmodule TransportWeb.EspaceProducteurControllerTest do
  use Oban.Testing, repo: DB.Repo
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Plug.Test, only: [init_test_session: 2]
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "renders successfully and finds the dataset using organization IDs", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: dataset_datagouv_id} =
        dataset = insert(:dataset, custom_title: custom_title = "Foobar")

      %DB.Resource{datagouv_id: resource_datagouv_id} = resource = insert(:resource, dataset: dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, 2, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 2, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_datagouv_id)
      end)

      td_text = fn doc ->
        doc |> Floki.find("td.align-right") |> Floki.text() |> String.replace(~r/(\s)+/, " ") |> String.trim()
      end

      doc =
        conn
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert doc |> Floki.find("h2") |> Floki.text() == custom_title

      assert td_text.(doc) == "Modifier la ressource Supprimer la ressource"

      # With a reuser improved data
      insert(:reuser_improved_data, dataset: dataset, resource: resource)

      doc =
        conn
        |> init_test_session(current_user: %{})
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
      } = insert(:dataset, custom_logo: "https://example.com/pic.png")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id -> {:ok, generate_dataset_payload(datagouv_id)} end)

      content =
        conn
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :edit_dataset, dataset_id))
        |> html_response(200)

      assert content
             |> Floki.parse_document!()
             |> Floki.find(~s{.producer-actions button[type="submit"]})
             |> Floki.text() =~ "Supprimer le logo personnalisé"
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
        |> init_test_session(current_user: %{})
        |> post(espace_producteur_path(conn, :upload_logo, dataset.id), %{"upload" => %{"file" => %Plug.Upload{}}})

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "uploads the logo to S3, enqueue a job and redirect", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)

      filename = "sample.jpg"
      local_path = System.tmp_dir!() |> Path.join(filename)
      upload_path = "tmp_#{datagouv_id}.jpg"

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

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
        |> init_test_session(current_user: %{"id" => contact.datagouv_user_id})
        |> post(espace_producteur_path(conn, :upload_logo, dataset.id), %{
          "upload" => %{"file" => %Plug.Upload{path: local_path, filename: filename}}
        })

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.CustomLogoConversionJob",
                 args: %{"datagouv_id" => ^datagouv_id, "path" => ^upload_path}
               }
             ] = all_enqueued()

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

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
        |> init_test_session(current_user: %{})
        |> delete(espace_producteur_path(conn, :remove_custom_logo, dataset.id))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "deletes objects and resets custom logos", %{conn: conn} do
      custom_logo_path = "#{Ecto.UUID.generate()}.png"
      custom_full_logo_path = "#{Ecto.UUID.generate()}_full.png"
      bucket_url = Transport.S3.permanent_url(:logos)

      %DB.Dataset{organization_id: organization_id} =
        dataset =
        insert(:dataset,
          custom_logo: Path.join(bucket_url, custom_logo_path),
          custom_full_logo: Path.join(bucket_url, custom_full_logo_path)
        )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Transport.Test.S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:logos), custom_logo_path)
      Transport.Test.S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:logos), custom_full_logo_path)

      conn =
        conn
        |> init_test_session(current_user: %{})
        |> delete(espace_producteur_path(conn, :remove_custom_logo, dataset.id))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

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
        |> init_test_session(%{current_user: %{}})
        |> get(espace_producteur_path(conn, :proxy_statistics))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

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

      html =
        conn
        |> init_test_session(%{current_user: %{}})
        |> get(espace_producteur_path(conn, :proxy_statistics))
        |> html_response(200)

      assert html =~ "Statistiques des requêtes gérées par le proxy"
      assert html =~ "<strong>\n2\n    </strong>\nrequêtes gérées par le proxy au cours des 15 derniers jours"
      assert html =~ "<strong>\n1\n    </strong>\nrequêtes transmises au serveur source au cours des 15 derniers jours"
    end
  end

  describe "download_statistics_csv" do
    test "requires authentication", %{conn: conn} do
      conn |> get(espace_producteur_path(conn, :download_statistics_csv)) |> assert_redirects_to_info_page()
    end

    test "redirects when there is an error when fetching datasets", %{conn: conn} do
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> {:error, nil} end)

      conn =
        conn
        |> init_test_session(%{current_user: %{}})
        |> get(espace_producteur_path(conn, :download_statistics_csv))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "renders successfully with a datagouv resource", %{conn: conn} do
      dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/url", title: "GTFS.zip")

      assert DB.Resource.hosted_on_datagouv?(resource)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

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
        |> init_test_session(%{current_user: %{}})
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
        |> init_test_session(%{current_user: %{}})
        |> get(espace_producteur_path(conn, :proxy_statistics_csv))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

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

      response =
        conn
        |> init_test_session(%{current_user: %{}})
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
    test "we can show the form of an existing resource", %{conn: conn} do
      conn = conn |> init_test_session(%{current_user: %{}})
      resource_datagouv_id = "resource_dataset_id"

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        insert(:dataset, custom_title: custom_title = "Base Nationale des Lieux de Covoiturage")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_datagouv_id)
      end)

      html =
        conn
        |> get(espace_producteur_path(conn, :edit_resource, dataset_id, resource_datagouv_id))
        |> html_response(200)

      doc = html |> Floki.parse_document!()
      assert_breadcrumb_content(html, ["Votre espace producteur", custom_title, "Modifier une ressource"])
      # Title
      assert doc |> Floki.find("h2") |> Floki.text() == "Modification d’une ressource"
      assert html =~ "bnlc.csv"
      assert html =~ "csv"
      assert html =~ "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv"
    end

    test "we can show the form for a new resource", %{conn: conn} do
      conn = conn |> init_test_session(%{current_user: %{}})

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        insert(:dataset, custom_title: custom_title = "Base Nationale des Lieux de Covoiturage")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id -> dataset_datagouv_get_response(dataset_datagouv_id) end)

      doc =
        conn
        |> get(espace_producteur_path(conn, :new_resource, dataset_id))
        |> html_response(200)
        |> Floki.parse_document!()

      assert_breadcrumb_content(doc, ["Votre espace producteur", custom_title, "Nouvelle ressource"])
      # Title
      assert doc |> Floki.find("h2") |> Floki.text() == "Ajouter une nouvelle ressource"
    end

    test "we can add a new resource with a URL", %{conn: conn} do
      %DB.Dataset{datagouv_id: dataset_datagouv_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      conn = conn |> init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})

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
            "dataset_id" => dataset_datagouv_id,
            "format" => "csv",
            "title" => "Test",
            "url" => "https://example.com/my_csv_resource.csv"
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
                   "dataset_datagouv_id" => ^dataset_datagouv_id
                 }
               }
             ] = DB.Repo.all(DB.FeatureUsage)
    end

    test "we can show the delete confirmation page", %{conn: conn} do
      conn = conn |> init_test_session(%{current_user: %{}})
      resource_datagouv_id = "resource_dataset_id"

      %DB.Dataset{id: dataset_id, datagouv_id: dataset_datagouv_id, organization_id: organization_id} =
        insert(:dataset, custom_title: custom_title = "Base Nationale des Lieux de Covoiturage")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^dataset_datagouv_id ->
        dataset_datagouv_get_response(dataset_datagouv_id, resource_datagouv_id)
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
      %DB.Dataset{datagouv_id: dataset_datagouv_id, resources: [%DB.Resource{datagouv_id: resource_datagouv_id}]} =
        insert(:dataset, resources: [insert(:resource)])

      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      conn = conn |> init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})

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

      assert location == page_path(conn, :espace_producteur)
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
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :reuser_improved_data, 42, 1337))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "we can see reuser improved data", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset)

      reuser_improved_data =
        insert(:reuser_improved_data, dataset: dataset, resource: resource) |> DB.Repo.preload([:organization])

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id -> {:ok, generate_dataset_payload(datagouv_id)} end)

      html =
        conn
        |> init_test_session(current_user: %{})
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
        |> init_test_session(%{current_user: %{}})
        |> get(espace_producteur_path(conn, :download_statistics))

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end

    test "renders successfully", %{conn: conn} do
      dataset = insert(:dataset)

      resource =
        insert(:resource,
          title: "gtfs.zip",
          format: "GTFS",
          url: "https://static.data.gouv.fr/example.zip",
          dataset: dataset
        )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      year_month = Date.utc_today() |> Date.to_iso8601() |> String.slice(0..6)

      insert(:resource_monthly_metric,
        resource_datagouv_id: resource.datagouv_id,
        metric_name: :downloads,
        count: 2_000,
        year_month: year_month
      )

      html =
        conn
        |> init_test_session(%{current_user: %{}})
        |> get(espace_producteur_path(conn, :download_statistics))
        |> html_response(200)

      assert html =~ "<h2>Statistiques de téléchargements</h2>"

      assert html |> Floki.parse_document!() |> Floki.find("table") == [
               {"table", [{"class", "table small-padding"}],
                [
                  {"thead", [],
                   [
                     {"tr", [],
                      [
                        {"th", [], ["Resource"]},
                        {"th", [], ["Ressource"]},
                        {"th", [], ["Téléchargements de l'année 2025"]}
                      ]}
                   ]},
                  {"tbody", [],
                   [
                     {"tr", [],
                      [
                        {"td", [{"rowspan", "1"}], [dataset.custom_title]},
                        {"td", [], [resource.title <> " ", {"span", [{"class", "label"}], [resource.format]}]},
                        {"td", [], ["\n2 000\n                "]}
                      ]}
                   ]}
                ]}
             ]
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

  defp dataset_datagouv_get_response(dataset_datagouv_id, resource_datagouv_id \\ "resource_id_1") do
    {:ok,
     datagouv_dataset_response(%{
       "id" => dataset_datagouv_id,
       "title" => "Base Nationale des Lieux de Covoiturage",
       "resources" =>
         generate_resources_payload(
           title: "bnlc.csv",
           url: "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv",
           id: resource_datagouv_id,
           format: "csv"
         )
     })}
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
end
