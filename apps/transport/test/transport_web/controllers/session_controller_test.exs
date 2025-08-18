defmodule TransportWeb.SessionControllerTest do
  use Oban.Testing, repo: DB.Repo
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Mox
  import Plug.Test
  import TransportWeb.SessionController

  doctest TransportWeb.SessionController
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Datagouvfr.Authentication.Mock, Datagouvfr.Authentication.Dummy)
    Mox.stub_with(Datagouvfr.Client.User.Mock, Datagouvfr.Client.User.Dummy)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "GET /login/callback", %{conn: conn} do
    user_params = %{
      "first_name" => first_name = "John",
      "last_name" => last_name = "Doe",
      "id" => datagouv_user_id = "user_id_1",
      "email" => email = "email@example.fr",
      "organizations" => [
        %{
          "acronym" => nil,
          "badges" => [%{"kind" => "certified"}, %{"kind" => "public-service"}],
          "id" => organization_id = "5abca8d588ee386ee6ece479",
          "logo" => logo = "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
          "logo_thumbnail" =>
            logo_thumbnail = "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
          "name" => organization_name = "Point d'Accès National transport.data.gouv.fr",
          "slug" => organization_slug = "equipe-transport-data-gouv-fr"
        }
      ]
    }

    expect(Datagouvfr.Client.User.Mock, :me, fn %Plug.Conn{} -> {:ok, user_params} end)

    assert [] == DB.Repo.all(DB.Contact)
    conn = conn |> get(session_path(conn, :create, %{"code" => "secret"}))

    current_user = get_session(conn, :current_user)

    assert %{
             "id" => ^datagouv_user_id,
             "email" => ^email,
             "first_name" => ^first_name,
             "last_name" => ^last_name,
             "is_admin" => true,
             # No active dataset for this users' organizations
             "is_producer" => false
           } = current_user

    refute Map.has_key?(current_user, "avatar")
    refute Map.has_key?(current_user, "organizations")

    assert redirected_to(conn, 302) == "/"

    # Token has been saved to `datagouv_token` key.
    assert conn.assigns[:datagouv_token] == Datagouvfr.Authentication.Dummy.get_token!(%{}) |> Map.fetch!(:token)

    # A `DB.Contact` has been created for this user
    assert [
             %DB.Contact{
               first_name: ^first_name,
               last_name: ^last_name,
               email: ^email,
               organization: ^organization_name,
               datagouv_user_id: ^datagouv_user_id,
               last_login_at: last_login_at,
               creation_source: :datagouv_oauth_login
             }
           ] = DB.Repo.all(DB.Contact)

    assert [
             %DB.Organization{
               id: ^organization_id,
               slug: ^organization_slug,
               name: ^organization_name,
               logo_thumbnail: ^logo_thumbnail,
               logo: ^logo,
               acronym: nil,
               badges: [%{"kind" => "certified"}, %{"kind" => "public-service"}]
             }
           ] = DB.Repo.all(DB.Organization)

    assert [
             %DB.Organization{id: ^organization_id}
           ] = DB.Contact |> DB.Repo.one!() |> DB.Repo.preload(:organizations) |> Map.fetch!(:organizations)

    assert_in_delta last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1
  end

  test "save_current_user", %{conn: conn} do
    pan_org = %{"slug" => "equipe-transport-data-gouv-fr", "name" => "PAN", "id" => org_id = Ecto.UUID.generate()}

    assert TransportWeb.Session.admin?(%{"organizations" => [pan_org]})
    refute TransportWeb.Session.producer?(%{"organizations" => [pan_org]})
    insert(:dataset, organization_id: org_id)
    # You're a producer if you're a member of an org with an active dataset
    assert TransportWeb.Session.producer?(%{"organizations" => [pan_org]})

    user_params = %{"foo" => "bar", "organizations" => [pan_org]}

    assert %{"foo" => "bar", "is_admin" => true, "is_producer" => true} ==
             conn |> init_test_session(%{}) |> save_current_user(user_params) |> get_session(:current_user)
  end

  test "GET /login/callback and redirection to /datasets", %{conn: conn} do
    conn =
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))

    assert redirected_to(conn, 302) == "/datasets"
  end

  describe "find_or_create_contact" do
    test "when contact exists, updates attributes coming from data.gouv.fr and the last_login_at" do
      contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
      assert contact.last_login_at == nil

      find_or_create_contact(%{
        "id" => datagouv_user_id,
        "first_name" => contact.first_name,
        "last_name" => contact.last_name,
        "email" => new_email = "#{Ecto.UUID.generate()}@example.fr",
        "organizations" => []
      })

      contact = DB.Repo.reload!(contact)

      assert contact.email == new_email
      assert_in_delta contact.last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1

      assert all_enqueued() |> Enum.empty?()
    end

    test "when contact exists with a mailing_list_title, don't update (first|last)_name" do
      contact =
        insert_contact(%{
          first_name: nil,
          last_name: nil,
          mailing_list_title: mailing_list_title = "Équipe data",
          datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()
        })

      find_or_create_contact(%{
        "id" => datagouv_user_id,
        "first_name" => "Équipe data",
        "last_name" => "CD42",
        "email" => contact.email,
        "organizations" => []
      })

      contact = DB.Repo.reload!(contact)

      assert %DB.Contact{first_name: nil, last_name: nil, mailing_list_title: ^mailing_list_title} = contact
      assert_in_delta contact.last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1

      assert all_enqueued() |> Enum.empty?()
    end

    test "can find a contact using its email address and sets the datagouv_user_id" do
      %DB.Contact{id: contact_id, datagouv_user_id: nil} = contact = insert_contact()

      find_or_create_contact(%{
        "id" => datagouv_user_id = Ecto.UUID.generate(),
        "first_name" => new_first_name = "Oka",
        "last_name" => last_name = contact.last_name,
        # We should perform a lowercase comparison for the email address
        "email" => String.upcase(contact.email),
        "organizations" => []
      })

      contact = DB.Repo.reload!(contact)

      assert %DB.Contact{first_name: ^new_first_name, last_name: ^last_name, datagouv_user_id: ^datagouv_user_id} =
               contact

      assert_in_delta contact.last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.CreateTokensJob",
                 args: %{"contact_id" => ^contact_id, "action" => "create_token_for_contact"},
                 state: "scheduled"
               },
               %Oban.Job{
                 worker: "Transport.Jobs.PromoteProducerSpaceJob",
                 args: %{"contact_id" => ^contact_id},
                 state: "scheduled"
               }
             ] = all_enqueued()
    end

    test "creates a contact when it doesn't exist" do
      assert DB.Contact |> DB.Repo.all() |> Enum.empty?()

      find_or_create_contact(%{
        "id" => datagouv_user_id = Ecto.UUID.generate(),
        "first_name" => first_name = "John",
        "last_name" => last_name = "Doe",
        "email" => email = "email@example.fr",
        "organizations" => [
          %{
            "acronym" => nil,
            "badges" => [],
            "id" => org_id = "5abca8d588ee386ee6ece479",
            "logo" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
            "logo_thumbnail" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
            "name" => org_name = "Corp Inc",
            "slug" => org_slug = Ecto.UUID.generate()
          }
        ]
      })

      assert [
               %DB.Contact{
                 id: contact_id,
                 first_name: ^first_name,
                 last_name: ^last_name,
                 datagouv_user_id: ^datagouv_user_id,
                 email: ^email,
                 organization: ^org_name,
                 last_login_at: last_login_at,
                 creation_source: :datagouv_oauth_login
               }
             ] = DB.Contact |> DB.Repo.all()

      assert [
               %DB.Organization{id: ^org_id, name: ^org_name, slug: ^org_slug}
             ] = DB.Organization |> DB.Repo.all()

      assert_in_delta last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.CreateTokensJob",
                 args: %{"contact_id" => ^contact_id, "action" => "create_token_for_contact"},
                 state: "scheduled"
               },
               %Oban.Job{
                 worker: "Transport.Jobs.PromoteProducerSpaceJob",
                 args: %{"contact_id" => ^contact_id},
                 state: "scheduled"
               }
             ] = all_enqueued()
    end
  end
end
