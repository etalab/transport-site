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
      conn = conn |> get(espace_producteur_path(conn, :edit_dataset, 42))
      assert redirected_to(conn, 302) =~ "/login"
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
      %DB.Dataset{organization_id: organization_id} = dataset = insert(:dataset, custom_title: custom_title = "Foobar")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      content =
        conn
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))
        |> html_response(200)

      assert custom_title == content |> Floki.parse_document!() |> Floki.find("h2") |> Floki.text()
    end

    test "when a custom logo is set", %{conn: conn} do
      dataset = insert(:dataset, custom_logo: "https://example.com/pic.png")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      content =
        conn
        |> init_test_session(current_user: %{})
        |> get(espace_producteur_path(conn, :edit_dataset, dataset.id))
        |> html_response(200)

      assert content =~
               "Vous avez actuellement un logo personnalisé. Si vous souhaitez le retirer ou le mettre à jour, veuillez contacter notre équipe."
    end
  end

  describe "upload_logo" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> post(espace_producteur_path(conn, :upload_logo, 42), %{"upload" => %{"file" => %Plug.Upload{}}})
      assert redirected_to(conn, 302) =~ "/login"
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

  describe "proxy_statistics" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> get(espace_producteur_path(conn, :proxy_statistics))

      assert redirected_to(conn, 302) =~ "/login"
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
end
