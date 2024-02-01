defmodule TransportWeb.EspaceProducteurControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Plug.Test, only: [init_test_session: 2]
  import Mox
  import Swoosh.TestAssertions

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

      assert content
             |> Floki.parse_document!()
             |> Floki.find(~s{.espace-producteur-section button[type="submit"]})
             |> Floki.text() =~ "Supprimer le logo personnalisé"
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

      conn =
        conn
        |> init_test_session(current_user: %{"email" => user_email})
        |> post(espace_producteur_path(conn, :upload_logo, dataset.id), %{
          "upload" => %{"file" => %Plug.Upload{path: local_path, filename: filename}}
        })

      assert redirected_to(conn, 302) == page_path(conn, :espace_producteur)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Votre logo a bien été reçu. Nous reviendrons vers vous rapidement."

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{"", "contact@transport.data.gouv.fr"}],
                             subject: ^email_subject,
                             text_body: text_body,
                             html_body: nil
                           } ->
        assert text_body == """
               Bonjour,

               Un logo personnalisé vient d'être envoyé.

               Scripts à exécuter :
               s3cmd mv s3://transport-data-gouv-fr-logos-test/#{upload_path} /tmp/#{upload_path}
               elixir scripts/custom_logo.exs /tmp/#{upload_path} #{datagouv_id}

               Personne à contacter :
               #{user_email}
               """
      end)
    end
  end

  describe "remove_custom_logo" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> delete(espace_producteur_path(conn, :remove_custom_logo, 42))
      assert redirected_to(conn, 302) =~ "/login"
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

      assert %DB.Dataset{custom_logo: nil, custom_full_logo: nil} = DB.Repo.reload!(dataset)
    end
  end
end
