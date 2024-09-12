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
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} =
        dataset = insert(:dataset, custom_title: custom_title = "Foobar")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, fn ^datagouv_id -> {:ok, generate_dataset_payload(datagouv_id)} end)

      content =
        conn
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))
        |> html_response(200)

      assert custom_title == content |> Floki.parse_document!() |> Floki.find("h2") |> Floki.text()
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
             |> Floki.find(~s{.espace-producteur-section button[type="submit"]})
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

    test "uploads the logo to S3, send an email and redirect", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)

      filename = "sample.jpg"
      local_path = System.tmp_dir!() |> Path.join(filename)
      upload_path = "tmp_#{datagouv_id}.jpg"
      user_email = "john@example.com"

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

      conn =
        conn
        |> init_test_session(current_user: %{"email" => user_email})
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
      assert html =~ "<strong>2</strong>\nrequêtes gérées par le proxy au cours des 15 derniers jours"
      assert html =~ "<strong>1</strong>\nrequêtes transmises au serveur source au cours des 15 derniers jours"
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
      conn = conn |> init_test_session(%{current_user: %{}})

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

      conn = conn |> init_test_session(%{current_user: %{}})

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
    end
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
