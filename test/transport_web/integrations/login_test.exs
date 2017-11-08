defmodule TransportWeb.Integrations.LoginTest do
  @moduledoc """
  When I click to open my data,
  And I'm not logged in, 
  I want after I'm logged in to be redirected to the organizations
  """

  use TransportWeb.ConnCase, async: true
  use Hound.Helpers
  alias URI

  hound_session()

  @tag :integration
  test "When I'm not logged in, and I click on a link with an authorization required, I'll be redirected to the same page" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    # I can see a log in / sign up link
    click({:class, "hero__link--open"})

    assert "redirect_path=%2Fuser%2Forganizations" == URI.parse(current_url()).query
  end
end
