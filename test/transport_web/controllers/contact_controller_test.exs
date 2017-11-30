defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase

  test "GET /contact", %{conn: conn} do
    conn = conn
    |> get(contact_path(conn, :form))

    assert html_response(conn, 200) =~ "<form"
  end
end
