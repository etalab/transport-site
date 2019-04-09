defmodule TransportWeb.Integration.ContactTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [], async: false
  use TransportWeb.UserFacingCase

  @tag :integration
  test "add a button to contact the team and ask for help" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    :class
    |> find_element("mail__button")
    |> find_within_element(:class, "icon--envelope")
    |> assert
  end
end
