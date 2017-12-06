defmodule TransportWeb.Integration.ContactTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.UserFacingCase

  @tag :integration
  test "add a button to contact the team and ask for help" do
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
