defmodule TransportWeb.LoginTest do
  @moduledoc """
  When I click to open my data,
  And I see a page explaining me I'll be redirected to data.gouv.fr
  I want to understand what's data.gouv.fr,
  And I want to understand what's the relationship between data.gouv.fr and Transport,
  And I want to know exactly what I'm supposed to do,
  so I can be reassured that I'm doing the right thing,
  and that I wont be left to my fate.
  """

  use TransportWeb.ConnCase, async: true
  use Hound.Helpers

  hound_session()

  @tag :integration
  test "I can see a log in link" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    assert page_source() =~ "S'identifier"
  end
end
