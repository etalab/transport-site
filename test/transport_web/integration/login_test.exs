defmodule TransportWeb.Integrations.LoginTest do
  use TransportWeb.ConnCase, async: true
  use Hound.Helpers
  alias URI

  hound_session()

  @tag :integration
  test "adds a redirect path to login link with current path" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    click({:class, "hero__link--open"})

    assert "redirect_path=%2Fuser%2Forganizations" == URI.parse(current_url()).query
  end
end
