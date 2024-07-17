defmodule TransportWeb.ReuserSpaceControllerTest do
  # `async: false` because we change the app config in a test
  use TransportWeb.ConnCase, async: false
  import DB.Factory

  @home_url reuser_space_path(TransportWeb.Endpoint, :espace_reutilisateur)

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "espace_reutilisateur" do
    test "logged out", %{conn: conn} do
      conn = conn |> get(@home_url)
      assert redirected_to(conn, 302) == page_path(conn, :infos_reutilisateurs)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    end

    test "logged in", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      content =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)

      # Feedback form is displayed
      refute content |> Floki.parse_document!() |> Floki.find("form.feedback-form") |> Enum.empty?()
    end

    test "reuser space disabled by killswitch", %{conn: conn} do
      old_value = Application.fetch_env!(:transport, :disable_reuser_space)
      Application.put_env(:transport, :disable_reuser_space, true)
      conn = Plug.Test.init_test_session(conn, %{current_user: %{}})
      refute TransportWeb.Session.display_reuser_space?(conn)
      conn = conn |> get(@home_url)
      assert redirected_to(conn, 302) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "La fonctionnalité n'est pas disponible pour le moment"
      Application.put_env(:transport, :disable_reuser_space, old_value)
    end
  end

  describe "datasets_edit" do
    test "logged out", %{conn: conn} do
      conn = conn |> get(reuser_space_path(conn, :datasets_edit, 42))
      assert redirected_to(conn, 302) == page_path(conn, :infos_reutilisateurs)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    end

    test "logged in, the requested dataset is not in the user's favorites", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)

      conn =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(reuser_space_path(conn, :datasets_edit, dataset.id))

      assert redirected_to(conn, 302) == reuser_space_path(conn, :espace_reutilisateur)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "logged in, with a favorited dataset", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> get(reuser_space_path(conn, :datasets_edit, dataset.id))
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find(".reuser-space-section h2")
             |> Floki.text() == dataset.custom_title
    end
  end

  describe "unfavorite" do
    test "requested dataset is not in the user's favorites", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)

      conn =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> post(reuser_space_path(conn, :unfavorite, dataset.id))

      assert redirected_to(conn, 302) == reuser_space_path(conn, :espace_reutilisateur)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Impossible de récupérer ce jeu de données pour le moment"
    end

    test "with a favorite dataset", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset, custom_title: "FooBar")
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: dataset.id,
        source: :user,
        reason: :expiration,
        role: :reuser
      )

      conn =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> post(reuser_space_path(conn, :unfavorite, dataset.id))

      assert redirected_to(conn, 302) == reuser_space_path(conn, :espace_reutilisateur)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "FooBar a été retiré de vos favoris"

      assert %DB.Contact{notification_subscriptions: [], followed_datasets: []} =
               DB.Repo.preload(contact, [:followed_datasets, :notification_subscriptions])
    end
  end
end
