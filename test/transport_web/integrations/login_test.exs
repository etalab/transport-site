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

    assert "next=%2Ffr%2Fadmin%2Fdataset%2Fnew%2F" == URI.parse(current_url()).query
  end
end
