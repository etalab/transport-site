defmodule TransportWeb.ReuseDataTest do
  @moduledoc """
  When the Transport team direct me to transport.beta.gouv.fr
  I want to have an easy way to explore which data is available,
  and be able to download it,
  so I can quickly integrate to my product(s).
  """

  use TransportWeb.ConnCase, async: true
  use Hound.Helpers

  hound_session()

  @tag :integration
  test "I can click on the map to reuse transport data" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    click({:css, "svg > g > path"})

    find_element(:class, "map__link")
    |> attribute_value("href")
    |> Kernel.=~("mailto:contact@transport.beta.gouv.fr")
    |> assert
  end

  @tag :integration
  test "I can click on a button to see available datasets" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    click({:class, "hero__link--reuse"})

    assert visible_page_text() =~ "Jeux de données disponibles"

    find_element(:class, "shortlist")
    |> find_within_element(:class, "shortlist-description")
    |> find_within_element(:tag, "h1")
    |> inner_text
    |> Kernel.=~("Horaires et arrêts du réseau IRIGO - format GTFS")
    |> assert
  end

  @tag :integration
  test "I can download a dataset from the list of available datasets" do
    @endpoint
    |> page_url(:shortlist)
    |> navigate_to

    find_element(:class, "download")
    |> find_within_element(:link_text, "Télécharger")
    |> attribute_value("href")
    |> Kernel.=~("zip")
    |> assert
  end
end
