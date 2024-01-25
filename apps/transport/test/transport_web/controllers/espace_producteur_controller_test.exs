defmodule TransportWeb.EspaceProducteurControllerTest do
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
      %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id, custom_title: custom_title} =
        dataset = insert(:dataset)

      filename = "sample.jpg"
      local_path = System.tmp_dir!() |> Path.join("#{filename}")
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

      email_subject = "Logo personnalisé : #{custom_title}"

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr" = _display_name,
                               "contact@transport.data.gouv.fr" = _from,
                               "contact@transport.data.gouv.fr" = _to,
                               "contact@transport.data.gouv.fr" = _reply_to,
                               ^email_subject,
                               body,
                               "" ->
        assert body == """
               Bonjour,

               Un logo personnalisé vient d'être envoyé.

               Scripts à exécuter :
               s3cmd mv s3://transport-data-gouv-fr-logos-test/#{upload_path} /tmp/#{upload_path}
               elixir scripts/custom_logo.exs /tmp/#{upload_path} #{datagouv_id}

               Personne à contacter :
               #{user_email}
               """

        :ok
      end)

      conn =
        conn
        |> init_test_session(current_user: %{"email" => user_email})
        |> post(espace_producteur_path(conn, :upload_logo, dataset.id), %{
          "upload" => %{"file" => %Plug.Upload{path: local_path, filename: filename}}
        })

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Votre logo a bien été reçu. Nous reviendrons vers vous rapidement."
    end
  end
end
