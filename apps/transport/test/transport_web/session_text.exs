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

  test "is_admin?" do
    refute is_admin?(%{"organizations" => []})
    refute is_admin?(%{"organizations" => [%{"slug" => "foo"}]})
    assert is_admin?(%{"organizations" => [pan_org()]})
  end

  describe "reader" do
    test "is_admin?" do
      refute is_admin?(Plug.Test.init_test_session(%Plug.Conn{}, %{}))
      assert is_admin?(Plug.Test.init_test_session(%Plug.Conn{}, %{current_user: %{"is_admin" => true}}))
      assert is_admin?(%{"is_admin" => true})
    end

    test "is_producer?" do
      assert is_producer?(Plug.Test.init_test_session(%Plug.Conn{}, %{current_user: %{"is_producer" => true}}))
      refute is_producer?(Plug.Test.init_test_session(%Plug.Conn{}, %{}))
    end
  end

  def pan_org do
    %{"slug" => "equipe-transport-data-gouv-fr", "name" => "PAN", "id" => @pan_org_id}
  end
end
