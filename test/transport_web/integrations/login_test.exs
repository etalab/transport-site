defmodule TransportWeb.Integration.LoginTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [], async: false
  use TransportWeb.UserFacingCase
  alias URI

  @tag :integration
  test "adds a redirect path to login link with current path" do
    @endpoint
    |> backoffice_page_url(:index)
    |> navigate_to

    assert "redirect_path=%2Fbackoffice" == URI.parse(current_url()).query
  end
end
