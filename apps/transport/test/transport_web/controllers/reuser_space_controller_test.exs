defmodule TransportWeb.ReuserSpaceControllerTest do
  # `async: false` because we change the app config in a test
  use TransportWeb.ConnCase, async: false
  import TransportWeb.ReuserSpaceController
  import DB.Factory

  @home_url reuser_space_path(TransportWeb.Endpoint, :espace_reutilisateur)
  @google_maps_org_id "63fdfe4f4cd1c437ac478323"

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

    test "logged in, dataset is eligible for the data sharing pilot", %{conn: conn} do
      organization = insert(:organization, id: @google_maps_org_id)
      dataset = insert(:dataset, custom_tags: ["repartage_donnees"], type: "public-transit")

      contact =
        insert_contact(%{
          datagouv_user_id: Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> get(reuser_space_path(conn, :datasets_edit, dataset.id))
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find("#data-sharing")
             |> Floki.text()
             |> String.trim() =~ "Étape 1 : sélectionnez la ressource initiale du producteur"
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

  test "add_improved_data", %{conn: conn} do
    %DB.Organization{id: organization_id} = organization = insert(:organization, id: @google_maps_org_id)
    %DB.Dataset{id: dataset_id} = insert(:dataset, custom_tags: ["repartage_donnees"], type: "public-transit")
    %DB.Resource{id: gtfs_id} = insert(:resource, dataset_id: dataset_id, format: "GTFS")

    %DB.Contact{id: contact_id} =
      contact =
      insert_contact(%{
        datagouv_user_id: Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

    download_url = "https://example.com/#{Ecto.UUID.generate()}"

    insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :follow_button)

    conn =
      conn
      |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
      |> post(
        reuser_space_path(conn, :add_improved_data, dataset_id, %{
          "resource_id" => gtfs_id,
          "organization_id" => @google_maps_org_id,
          "download_url" => download_url
        })
      )

    redirection_path = redirected_to(conn, 302)
    assert reuser_space_path(conn, :datasets_edit, dataset_id) == redirection_path
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vos données améliorées ont bien été sauvegardées."

    assert [
             %DB.ReuserImprovedData{
               dataset_id: ^dataset_id,
               resource_id: ^gtfs_id,
               contact_id: ^contact_id,
               organization_id: ^organization_id,
               download_url: ^download_url
             }
           ] = DB.ReuserImprovedData |> DB.Repo.all()

    assert get(recycle(conn), redirection_path)
           |> html_response(200)
           |> Floki.parse_document!()
           |> Floki.find("#data-sharing p.notification")
           |> Floki.text()
           |> String.trim() == "Vous avez déjà partagé des données améliorées pour ce jeu de données, merci !"
  end

  describe "data_sharing_pilot?" do
    test "contact is not a member of an eligible organization" do
      dataset = %DB.Dataset{type: "public-transit", custom_tags: ["repartage_donnees"]}
      contact = %DB.Contact{organizations: []}
      refute data_sharing_pilot?(dataset, contact)
    end

    test "dataset does not have the required tag" do
      dataset = %DB.Dataset{type: "public-transit", custom_tags: []}
      contact = %DB.Contact{organizations: [%DB.Organization{id: @google_maps_org_id}]}
      refute data_sharing_pilot?(dataset, contact)
    end

    test "dataset is eligible for contact" do
      dataset = %DB.Dataset{type: "public-transit", custom_tags: ["repartage_donnees"]}
      contact = %DB.Contact{organizations: [%DB.Organization{id: @google_maps_org_id}]}
      assert data_sharing_pilot?(dataset, contact)
    end
  end

  describe "settings" do
    test "link to settings is only visible by admins", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      href_attributes = fn %Plug.Conn{} = conn ->
        conn
        |> get(reuser_space_path(conn, :espace_reutilisateur))
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find(".action-panel a")
        |> Floki.attribute("a", "href")
      end

      # When contact is NOT an admin
      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> href_attributes.() == [reuser_space_path(conn, :notifications)]

      # When contact is an admin
      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id, "is_admin" => true}})
             |> href_attributes.() == [reuser_space_path(conn, :notifications), reuser_space_path(conn, :settings)]
    end

    test "no tokens", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> get(reuser_space_path(conn, :settings))
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find("p.notification")
             |> Floki.text()
             |> String.trim() == "Il n'y a pas de tokens pour le moment."
    end

    test "an existing token is displayed", %{conn: conn} do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          datagouv_user_id: Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      token = insert(:token, organization: organization, contact: contact, name: "Default")

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> get(reuser_space_path(conn, :settings))
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find("table tr td") == [
               {"td", [], [organization.name]},
               {"td", [], [token.name]},
               {"td", [], [{"code", [], [token.secret]}]}
             ]
    end
  end

  describe "new_token" do
    test "no organizations", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      doc =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(reuser_space_path(conn, :new_token))
        |> html_response(200)
        |> Floki.parse_document!()

      assert doc |> Floki.find(".panel form") |> Enum.empty?()

      assert doc
             |> Floki.find("p.notification.error")
             |> Floki.text()
             |> String.trim() == "Vous devez être membre d'une organisation pour créer un nouveau token."
    end

    test "member of an organization", %{conn: conn} do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          datagouv_user_id: Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      doc =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(reuser_space_path(conn, :new_token))
        |> html_response(200)
        |> Floki.parse_document!()

      refute doc |> Floki.find(".panel form") |> Enum.empty?()

      assert doc |> Floki.find("option") == [{"option", [{"value", organization.id}], [organization.name]}]
    end
  end

  test "create_new_token", %{conn: conn} do
    %DB.Organization{id: organization_id} = organization = insert(:organization)

    %DB.Contact{id: contact_id} =
      contact =
      insert_contact(%{
        datagouv_user_id: Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

    assert DB.Token |> DB.Repo.all() |> Enum.empty?()

    conn =
      conn
      |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
      |> post(reuser_space_path(conn, :create_new_token), %{organization_id: organization.id, name: name = "Name"})

    assert redirected_to(conn, 302) == reuser_space_path(conn, :settings)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Votre token a bien été créé"

    assert [%DB.Token{contact_id: ^contact_id, organization_id: ^organization_id, name: ^name}] = DB.Repo.all(DB.Token)
  end
end
