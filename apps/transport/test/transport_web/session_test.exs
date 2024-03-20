defmodule TransportWeb.SessionTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import TransportWeb.Session
  doctest TransportWeb.Session, import: true

  @pan_org_id Ecto.UUID.generate()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "is_producer?" do
    refute is_producer?(%{"organizations" => [pan_org()]})
    insert(:dataset, organization_id: @pan_org_id)
    # You're a producer if you're a member of an org with an active dataset
    assert is_producer?(%{"organizations" => [pan_org()]})
  end

  test "admin?" do
    refute admin?(%{"organizations" => []})
    refute admin?(%{"organizations" => [%{"slug" => "foo"}]})
    assert admin?(%{"organizations" => [pan_org()]})
  end

  describe "reader" do
    test "admin?" do
      refute admin?(Plug.Test.init_test_session(%Plug.Conn{}, %{}))
      assert admin?(Plug.Test.init_test_session(%Plug.Conn{}, %{current_user: %{"is_admin" => true}}))
      assert admin?(%Phoenix.LiveView.Socket{assigns: %{current_user: %{"is_admin" => true}}})
    end

    test "is_producer?" do
      assert is_producer?(Plug.Test.init_test_session(%Plug.Conn{}, %{current_user: %{"is_producer" => true}}))
      refute is_producer?(Plug.Test.init_test_session(%Plug.Conn{}, %{}))
    end
  end

  describe "set_is_producer" do
    test "no datasets" do
      assert %{"is_producer" => false} ==
               %Plug.Conn{}
               |> Plug.Test.init_test_session(%{current_user: %{}})
               |> set_is_producer([])
               |> Plug.Conn.get_session(:current_user)
    end

    test "2 datasets" do
      assert %{"is_producer" => true} ==
               %Plug.Conn{}
               |> Plug.Test.init_test_session(%{current_user: %{}})
               |> set_is_producer([build(:dataset), build(:dataset)])
               |> Plug.Conn.get_session(:current_user)
    end
  end

  def pan_org do
    %{"slug" => "equipe-transport-data-gouv-fr", "name" => "PAN", "id" => @pan_org_id}
  end
end
