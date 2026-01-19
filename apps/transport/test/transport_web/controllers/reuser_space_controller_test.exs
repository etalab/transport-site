defmodule TransportWeb.ReuserSpaceControllerTest do
  # `async: false` because we change the app config in a test
  use TransportWeb.ConnCase, async: false
  import TransportWeb.ReuserSpaceController
  import DB.Factory
  import Mox

  @home_url reuser_space_path(TransportWeb.Endpoint, :espace_reutilisateur)
  @google_maps_org_id "63fdfe4f4cd1c437ac478323"

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
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

    test "urgent issues are displayed", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset, is_available: false)
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _datagouv_id -> [] end)

      doc =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)
        |> Floki.parse_document!()

      assert doc |> Floki.find(~s|[data-name="important-information"] h2|) |> Floki.text() ==
               "Informations importantes concernant les ressources que vous suivez"

      # Check that one row is displayed with the expected content
      assert [row] = important_info_rows_without_recent_features(doc)

      # Check dataset link
      assert row |> Floki.find("a[href='/datasets/#{dataset.slug}']") |> Enum.any?()

      # Check resource link
      assert row |> Floki.find("a[href='/resources/#{resource.id}']") |> Enum.any?()

      # Check hide button is present
      assert row |> Floki.find("form.hide-alert-form") |> Enum.any?()
      assert row |> Floki.find("input[name='check_type'][value='unavailable_resource']") |> Enum.any?()

      # Check issue text
      assert row |> Floki.text() |> String.contains?("Ressource indisponible")

      # If we're in the first 7 days, recent_features row should be present
      all_tbody_rows = doc |> Floki.find(~s|[data-name="important-information"] tbody tr|)

      if Date.utc_today().day in 1..7 do
        assert length(all_tbody_rows) == 2
        assert Enum.any?(all_tbody_rows, &recent_features_row?/1)
      else
        assert length(all_tbody_rows) == 1
      end
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

      Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _datagouv_id -> [] end)

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

      Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _datagouv_id -> [] end)

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

      Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _datagouv_id -> [] end)

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

    Datagouvfr.Client.Discussions.Mock |> expect(:get, 2, fn _datagouv_id -> [] end)

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
    test "panel links", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> index_href_attributes() == [
               reuser_space_path(conn, :notifications),
               "https://www.data.gouv.fr/admin/reuses/new/",
               reuser_space_path(conn, :settings)
             ]
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

      token =
        insert_token(%{
          organization_id: organization.id,
          contact_id: contact.id,
          name: "Default"
        })

      insert(:default_token, token: token, contact: contact)

      organization_name = organization.name
      token_name = "#{token.name} (par défaut)"
      token_secret = token.secret

      assert [
               {"td", [], [^organization_name]},
               {"td", [], [{"b", [], [^token_name]}]},
               {"td", [], [{"code", [], [^token_secret]}]},
               {"td", [], [_]}
             ] =
               conn
               |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
               |> get(reuser_space_path(conn, :settings))
               |> html_response(200)
               |> Floki.parse_document!()
               |> Floki.find("table tr td")
    end

    test "personal token is displayed", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      token =
        insert_token(%{
          organization_id: nil,
          contact_id: contact.id,
          name: "Default"
        })

      insert(:default_token, token: token, contact: contact)

      organization_name = "Token personnel"
      token_name = "#{token.name} (par défaut)"
      token_secret = token.secret

      assert [
               {"td", [], [^organization_name]},
               {"td", [], [{"b", [], [^token_name]}]},
               {"td", [], [{"code", [], [^token_secret]}]},
               {"td", [], [_]}
             ] =
               conn
               |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
               |> get(reuser_space_path(conn, :settings))
               |> html_response(200)
               |> Floki.parse_document!()
               |> Floki.find("table tr td")
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

      assert doc |> Floki.find(".panel form option") == [{"option", [{"value", organization.id}], [organization.name]}]
    end
  end

  describe "create_new_token" do
    test "create a new token", %{conn: conn} do
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

      assert [
               %DB.Token{
                 id: token_id,
                 contact_id: ^contact_id,
                 organization_id: ^organization_id,
                 name: ^name
               }
             ] =
               DB.Repo.all(DB.Token)

      assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(contact, :default_tokens) |> Map.fetch!(:default_tokens)
    end

    test "creating a new token, with an error", %{conn: conn} do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          datagouv_user_id: Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      assert DB.Token |> DB.Repo.all() |> Enum.empty?()

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> post(reuser_space_path(conn, :create_new_token), %{organization_id: organization.id})
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find(".notification.error")
             |> Floki.text() == "name: can't be blank"

      assert [] = DB.Repo.all(DB.Token)
    end

    @tag :capture_log
    test "cannot pass a random organization_id", %{conn: conn} do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          datagouv_user_id: Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      assert DB.Token |> DB.Repo.all() |> Enum.empty?()

      assert_raise MatchError, fn ->
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> post(reuser_space_path(conn, :create_new_token), %{organization_id: Ecto.UUID.generate(), name: "Default"})
        |> html_response(200)
      end
    end

    test "creates a new token with an existing token", %{conn: conn} do
      %DB.Organization{id: organization_id} = organization = insert(:organization)

      %DB.Contact{id: contact_id} =
        contact =
        insert_contact(%{
          datagouv_user_id: Ecto.UUID.generate(),
          organizations: [organization |> Map.from_struct()]
        })

      token = insert_token(%{contact_id: contact_id, organization_id: organization_id})
      insert(:default_token, token: token, contact: contact)

      conn =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> post(reuser_space_path(conn, :create_new_token), %{organization_id: organization.id, name: name = "Name"})

      assert redirected_to(conn, 302) == reuser_space_path(conn, :settings)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Votre token a bien été créé"

      assert [
               %DB.Token{id: t1_id},
               %DB.Token{
                 contact_id: ^contact_id,
                 organization_id: ^organization_id,
                 name: ^name
               }
             ] =
               DB.Token |> DB.Repo.all() |> Enum.sort_by(& &1.inserted_at, DateTime)

      assert [%DB.Token{id: ^t1_id}] = DB.Repo.preload(contact, :default_tokens) |> Map.fetch!(:default_tokens)
    end
  end

  test "delete_token", %{conn: conn} do
    organization = insert(:organization)

    contact =
      insert_contact(%{
        datagouv_user_id: Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

    t1 = insert_token(%{contact_id: contact.id, organization_id: organization.id, name: "t1"})
    insert(:default_token, token: t1, contact: contact)

    t2 = insert_token(%{contact_id: contact.id, organization_id: organization.id, name: "t2"})

    conn =
      conn
      |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
      |> delete(reuser_space_path(conn, :delete_token, t2.id))

    assert redirected_to(conn, 302) == reuser_space_path(conn, :settings)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Votre token a bien été supprimé"

    assert t2 |> DB.Repo.reload() |> is_nil()
  end

  test "default_token", %{conn: conn} do
    organization = insert(:organization)

    %DB.Contact{id: contact_id} =
      contact =
      insert_contact(%{
        datagouv_user_id: Ecto.UUID.generate(),
        organizations: [organization |> Map.from_struct()]
      })

    %DB.Contact{id: c2_id} = c2 = insert_contact()

    t1 =
      insert_token(%{
        contact_id: contact.id,
        organization_id: organization.id,
        name: "t1"
      })

    insert(:default_token, token: t1, contact: contact)

    %DB.Token{id: t2_id} = t2 = insert_token(%{contact_id: contact.id, organization_id: organization.id, name: "t2"})
    insert(:default_token, token: t2, contact: c2)

    conn =
      conn
      |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
      |> post(reuser_space_path(conn, :default_token, t2.id))

    assert redirected_to(conn, 302) == reuser_space_path(conn, :settings)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Le token t2 est maintenant le token par défaut"

    assert [] = DB.Repo.preload(t1, :default_for_contacts) |> Map.fetch!(:default_for_contacts)

    assert [%DB.Contact{id: ^contact_id}, %DB.Contact{id: ^c2_id}] =
             DB.Repo.preload(t2, :default_for_contacts)
             |> Map.fetch!(:default_for_contacts)
             |> Enum.sort_by(& &1.inserted_at, DateTime)

    assert [%DB.Token{id: ^t2_id}] = DB.Repo.preload(contact, :default_tokens) |> Map.fetch!(:default_tokens)
  end

  test "contact can only have 1 default_token" do
    contact = insert_contact()
    t1 = insert_token()
    t2 = insert_token()

    insert(:default_token, contact: contact, token: t1)

    assert_raise Ecto.ConstraintError, ~r/default_token_contact_id_index/, fn ->
      insert(:default_token, contact: contact, token: t2)
    end
  end

  describe "hide_alert" do
    test "hides an alert for a resource", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset, is_available: false)
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      # The mock is called by ReuserData plug (1x) + controller checks (1x) = 2x per page load
      # We have 2 page loads (initial + after hide) + 1 redirect that also calls the plug
      Datagouvfr.Client.Discussions.Mock |> stub(:get, fn _datagouv_id -> [] end)

      # First, check that the alert is visible and notification badge shows 1
      doc =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)
        |> Floki.parse_document!()

      assert length(important_info_rows_without_recent_features(doc)) == 1
      assert doc |> Floki.find(".notification_badge") |> Floki.text() =~ "1"

      # Now hide the alert
      conn =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> post(reuser_space_path(conn, :hide_alert, dataset.id), %{
          "check_type" => "unavailable_resource",
          "resource_id" => to_string(resource.id)
        })

      assert redirected_to(conn, 302) == @home_url
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Information masquée pendant 7 jours"

      # Check the database
      assert [%DB.HiddenReuserAlert{} = hidden_alert] = DB.Repo.all(DB.HiddenReuserAlert)
      assert hidden_alert.contact_id == contact.id
      assert hidden_alert.dataset_id == dataset.id
      assert hidden_alert.check_type == :unavailable_resource
      assert hidden_alert.resource_id == resource.id
      assert hidden_alert.discussion_id == nil

      assert_in_delta hidden_alert.hidden_until |> DateTime.to_unix(),
                      DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.to_unix(),
                      1

      # Check that the alert is no longer visible and notification badge is gone
      doc =
        conn
        |> recycle()
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)
        |> Floki.parse_document!()

      assert Enum.empty?(important_info_rows_without_recent_features(doc))
      assert doc |> Floki.find(".notification_badge") |> Enum.empty?()
    end

    test "hides an alert for a discussion", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)
      discussion_id = Ecto.UUID.generate()

      Datagouvfr.Client.Discussions.Mock
      |> stub(:get, fn _datagouv_id ->
        [
          %{
            "id" => discussion_id,
            "title" => "Test discussion",
            "discussion" => [
              %{
                "posted_on" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ]
          }
        ]
      end)

      # First, check that the alert is visible
      doc =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)
        |> Floki.parse_document!()

      assert length(important_info_rows_without_recent_features(doc)) == 1

      # Now hide the alert
      conn =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> post(reuser_space_path(conn, :hide_alert, dataset.id), %{
          "check_type" => "recent_discussions",
          "discussion_id" => discussion_id
        })

      assert redirected_to(conn, 302) == @home_url
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Information masquée pendant 7 jours"

      # Check the database
      assert [%DB.HiddenReuserAlert{} = hidden_alert] = DB.Repo.all(DB.HiddenReuserAlert)
      assert hidden_alert.check_type == :recent_discussions
      assert hidden_alert.resource_id == nil
      assert hidden_alert.discussion_id == discussion_id

      # Check that the alert is no longer visible
      doc =
        conn
        |> recycle()
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)
        |> Floki.parse_document!()

      assert Enum.empty?(important_info_rows_without_recent_features(doc))
    end

    test "expired hidden alert reappears", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset, is_available: false)
      insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :follow_button)

      # Insert an expired hidden alert
      insert(:hidden_reuser_alert,
        contact_id: contact.id,
        dataset_id: dataset.id,
        check_type: :unavailable_resource,
        resource_id: resource.id,
        hidden_until: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      Datagouvfr.Client.Discussions.Mock |> stub(:get, fn _datagouv_id -> [] end)

      # Check that the alert is visible since it has expired
      doc =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)
        |> Floki.parse_document!()

      assert length(important_info_rows_without_recent_features(doc)) == 1
    end
  end

  def index_href_attributes(%Plug.Conn{} = conn) do
    conn
    |> get(reuser_space_path(conn, :espace_reutilisateur))
    |> html_response(200)
    |> Floki.parse_document!()
    |> Floki.find(".action-panel a")
    |> Floki.attribute("a", "href")
  end

  defp important_info_rows_without_recent_features(doc) do
    doc
    |> Floki.find(~s|[data-name="important-information"] tbody tr|)
    |> Enum.reject(&recent_features_row?/1)
  end

  defp recent_features_row?(row), do: row |> Floki.text() |> String.contains?("Nouvelles fonctionnalités")
end
