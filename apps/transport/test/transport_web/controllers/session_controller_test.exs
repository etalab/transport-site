defmodule TransportWeb.SessionControllerTest do
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
      "organizations" => [%{"slug" => "equipe-transport-data-gouv-fr", "name" => organization = "PAN"}]
    }

    expect(Datagouvfr.Client.User.Mock, :me, fn %Plug.Conn{} -> {:ok, user_params} end)

    assert [] == DB.Repo.all(DB.Contact)
    conn = conn |> get(session_path(conn, :create, %{"code" => "secret"}))
    current_user = get_session(conn, :current_user)

    assert redirected_to(conn, 302) == "/"
    assert Map.has_key?(current_user, "id") == true
    assert Map.has_key?(current_user, "avatar") == false

    # A `DB.Contact` has been created for this user
    assert [
             %DB.Contact{
               first_name: ^first_name,
               last_name: ^last_name,
               email: ^email,
               organization: ^organization,
               datagouv_user_id: ^datagouv_user_id,
               last_login_at: last_login_at
             }
           ] = DB.Repo.all(DB.Contact)

    assert_in_delta last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1
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
        "email" => new_email = "#{Ecto.UUID.generate()}@example.fr"
      })

      contact = DB.Repo.reload!(contact)

      assert contact.email == new_email
      assert_in_delta contact.last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1
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
        "email" => contact.email
      })

      contact = DB.Repo.reload!(contact)

      assert %DB.Contact{first_name: nil, last_name: nil, mailing_list_title: ^mailing_list_title} = contact
      assert_in_delta contact.last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1
    end

    test "can find a contact using its email address and sets the datagouv_user_id" do
      %DB.Contact{datagouv_user_id: nil} = contact = insert_contact()

      find_or_create_contact(%{
        "id" => datagouv_user_id = Ecto.UUID.generate(),
        "first_name" => new_first_name = "Oka",
        "last_name" => last_name = contact.last_name,
        "email" => contact.email,
        "organizations" => []
      })

      contact = DB.Repo.reload!(contact)

      assert %DB.Contact{first_name: ^new_first_name, last_name: ^last_name, datagouv_user_id: ^datagouv_user_id} =
               contact

      assert_in_delta contact.last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1
    end

    test "creates a contact when it doesn't exist" do
      assert DB.Contact |> DB.Repo.all() |> Enum.empty?()

      find_or_create_contact(%{
        "id" => datagouv_user_id = Ecto.UUID.generate(),
        "first_name" => first_name = "John",
        "last_name" => last_name = "Doe",
        "email" => email = "email@example.fr",
        "organizations" => [%{"name" => org_name = "Corp Inc"}]
      })

      assert [%DB.Contact{first_name: ^first_name, last_name: ^last_name, datagouv_user_id: ^datagouv_user_id, email: ^email, organization: ^org_name, last_login_at: last_login_at}] = DB.Contact |> DB.Repo.all()
      assert_in_delta last_login_at |> DateTime.to_unix(), DateTime.utc_now() |> DateTime.to_unix(), 1
    end
  end
end
