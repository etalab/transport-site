defmodule TransportWeb.LayoutViewTest do
  use TransportWeb.ConnCase, async: true
  import Plug.Test

  @moduletag :view

  setup do
    current_user = %{
      "avatar_thumbnail" => "https://avatar.co/tristram",
      "first_name" => "Tristram",
      "last_name" => "Gräbener"
    }

    {:ok, current_user: current_user}
  end

  test "renders avatar", %{conn: conn, current_user: current_user} do
    render =
      conn
      |> init_test_session(current_user: current_user)
      |> get("/")
      |> Map.get(:resp_body)

    assert render =~ current_user["avatar_thumbnail"]
    assert render =~ current_user["first_name"]
    assert render =~ current_user["last_name"]
  end
end
