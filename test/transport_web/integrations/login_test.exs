defmodule TransportWeb.Integration.LoginTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.UserFacingCase
  alias URI

  @tag :integration
  test "adds a redirect path to login link with current path" do
    @endpoint
    |> backoffice_url(:index)
    |> navigate_to

    assert "redirect_path=%2Fbackoffice" == URI.parse(current_url()).query
  end
end
