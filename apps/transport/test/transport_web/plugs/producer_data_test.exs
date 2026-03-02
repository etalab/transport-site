defmodule TransportWeb.Plugs.ProducerDataTest do
  use TransportWeb.ConnCase, async: false
  alias TransportWeb.Plugs.ProducerData
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  @cache_name Transport.Cache.Cachex.cache_name()

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)

    # Use a real in-memory cache for these tests to test the caching mecanism
    old_value = Application.fetch_env!(:transport, :cache_impl)
    Application.put_env(:transport, :cache_impl, Transport.Cache.Cachex)

    on_exit(fn ->
      Application.put_env(:transport, :cache_impl, old_value)
      Cachex.reset(@cache_name)
    end)

    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "call" do
    test "when user is a producer", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      %DB.Dataset{id: dataset_id, organization_id: organization_id, datagouv_id: datagouv_id} =
        dataset = insert(:dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

      Datagouvfr.Client.Organization.Mock
      |> expect(:get, fn ^organization_id, [restrict_fields: true] ->
        {:ok, %{"members" => [%{"user" => %{"id" => contact.datagouv_user_id}}]}}
      end)

      Datagouvfr.Client.Discussions.Mock |> expect(:get, fn ^datagouv_id -> [] end)

      current_user = %{"is_producer" => true, "id" => contact.datagouv_user_id}

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{current_user: current_user})
        |> assign(:current_user, current_user)
        |> ProducerData.call([])

      # Assigns have been saved
      assert %{
               datasets_checks: [
                 %{expiring_resource: [], invalid_resource: [], unavailable_resource: [], unanswered_discussions: []}
               ],
               datasets_for_user: [%DB.Dataset{id: ^dataset_id}]
             } = conn.assigns

      # Cache has been set
      assert ["datasets_checks::#{contact.datagouv_user_id}", "datasets_for_user::#{contact.datagouv_user_id}"] ==
               Cachex.keys!(@cache_name) |> Enum.sort()

      # With the appropriate TTL
      assert_in_delta Cachex.ttl!(@cache_name, "datasets_checks::#{contact.datagouv_user_id}"), :timer.minutes(30), 50
      assert_in_delta Cachex.ttl!(@cache_name, "datasets_for_user::#{contact.datagouv_user_id}"), :timer.minutes(30), 50
    end

    test "when user is a producer and there is an OAuth 2 error", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:error, "An error occured"} end)

      current_user = %{"is_producer" => true, "id" => contact.datagouv_user_id}

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{current_user: current_user})
        |> assign(:current_user, current_user)
        |> ProducerData.call([])

      # Assigns have been saved
      assert %{
               datasets_checks: [],
               datasets_for_user: {:error, "An error occured"}
             } = conn.assigns

      # Cache has not set
      assert [] == Cachex.keys!(@cache_name)
    end

    test "when user is not a producer", %{conn: conn} do
      assert %Plug.Conn{} = conn |> Phoenix.ConnTest.init_test_session(%{}) |> ProducerData.call([])
    end

    for method <- ["PUT", "POST", "DELETE"] do
      test "cache is deleted and skipped for #{method} request on espace_producteur", %{conn: conn} do
        contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
        random_cache_value = Ecto.UUID.generate()

        Cachex.put(@cache_name, "datasets_for_user::#{contact.datagouv_user_id}", random_cache_value)

        %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)

        Datagouvfr.Client.User.Mock
        |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

        Datagouvfr.Client.Organization.Mock
        |> expect(:get, fn ^organization_id, [restrict_fields: true] ->
          {:ok, %{"members" => [%{"user" => %{"id" => contact.datagouv_user_id}}]}}
        end)

        Datagouvfr.Client.Discussions.Mock |> expect(:get, fn ^datagouv_id -> [] end)

        current_user = %{"is_producer" => true, "id" => contact.datagouv_user_id}

        %{conn | method: unquote(method), request_path: "/espace_producteur/datasets"}
        |> Phoenix.ConnTest.init_test_session(%{current_user: current_user})
        |> assign(:current_user, current_user)
        |> ProducerData.call([])

        # Cache has not been set and has been deleted
        assert [] == Cachex.keys!(@cache_name)
      end
    end
  end
end
