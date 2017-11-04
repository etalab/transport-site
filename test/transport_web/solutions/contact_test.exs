defmodule TransportWeb.ContacTest do
  @moduledoc """
  When I'm on a page I want to be able to easily contact the team
  """

  use TransportWeb.ConnCase, async: true
  use Hound.Helpers

  hound_session()

  @tag :integration
  test "I can see a button to ask for help" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    assert visible_page_text() =~ "?"

    find_element(:class, "footer-help__round")
    |> inner_text
    |> Kernel.=~("?")
    |> assert
  end
end
