defmodule TransportWeb.LayoutViewTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: []
  import DB.Factory
  import Plug.Test

  @moduletag :view

  setup do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    current_user = %{
      "id" => contact.datagouv_user_id,
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
      |> get(~p"/")
      |> Map.get(:resp_body)

    assert render =~ current_user["avatar_thumbnail"]
    assert render =~ current_user["first_name"]
    assert render =~ current_user["last_name"]
  end
end
