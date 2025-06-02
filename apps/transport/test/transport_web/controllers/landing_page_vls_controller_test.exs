defmodule TransportWeb.LandingPageVLSControllerTest do
  use TransportWeb.ConnCase, async: true

  test "GET /landing-vls", %{conn: conn} do
    conn = conn |> get(~p"/landing-vls")

    html = conn |> html_response(200)

    assert html =~ "Accédez aux données"
  end
end
