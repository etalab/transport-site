defmodule TransportWeb.Solution.DataSharingTest do
  @moduledoc """
    When I've already published my data in data.gouv.fr,
    And the Transport team sends me an email to make my transportation data reusable,
    And I follow the link provided in that email,
    I want to know exactly why my data is not reusable,
    and how to make it reusable,
    and be able to contact the Transport team to ask them a question,
    so citizens can better profit of available public transportation.
  """

  use TransportWeb.ConnCase, async: true
  use TransportWeb.UserFacingCase

  @tag :solution
  test "I'm redirected to the login page when I'm not logged in" do
    @endpoint
    |> user_url(:organizations)
    |> navigate_to

    current_url()
    |> Kernel.=~("/login/explanation")
    |> assert

    find_element(:class, "message--info")
    |> inner_text
    |> Kernel.=~("connecté")
    |> assert
  end
end
