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

    # I can see a log in / sign up link
    click({:class, "navigation__link--login"})

    # I have an explanation of what data.gouv.fr is
    assert visible_page_text() =~ "plateforme ouverte des données publiques françaises"

    # I have an explanation of what the relationship is between data.gouv.fr and Transport
    assert visible_page_text() =~ "transport.data.gouv.fr est un site affilié à data.gouv.fr"

    # I have an explanation of what's going to happen and what I'm I supposed to do
    assert visible_page_text() =~ "créer un compte et/ou vous identifier"
    assert visible_page_text() =~ "autoriser transport.data.gouv.fr à utiliser votre compte data.gouv.fr"

    # I can click somewhere to start the log in / sign up process
    assert visible_page_text() =~ "S'identifier"

    # I can click somewhere to ask for help
    assert visible_page_text() =~ "Nous contacter"
  end
end
