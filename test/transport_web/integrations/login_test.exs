defmodule TransportWeb.Integration.LoginTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.UserFacingCase
  alias URI

  @tag :integration
  test "adds a redirect path to login link with current path" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    click({:class, "hero__link--open"})

    assert "redirect_path=%2Fuser%2Forganizations" == URI.parse(current_url()).query
  end
end
