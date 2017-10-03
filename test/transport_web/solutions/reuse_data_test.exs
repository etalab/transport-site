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
    home_url() |> navigate_to
    click({:css, "svg > g > path"})

    find_element(:class, "landing-reuse")
    |> attribute_value("href")
    |> Kernel.=~("mailto:contact@transport.beta.gouv.fr")
    |> assert
  end

  @tag :integration
  test "I can click on a button to see available datasets" do
    home_url() |> navigate_to
    click({:css, "section"})

    find_all_elements(:class, "landing-open")
    |> Enum.any?(fn(a) -> attribute_value(a, "href") =~ shortlist_url() end)
    |> assert
  end

  @tag :integration
  test "I can download a datasets on /shortlist" do
    shortlist_url() |> navigate_to

    find_element(:class, "download")
    |> find_within_element(:tag, "a")
    |> attribute_value("href")
    |> Kernel.=~("zip")
    |> assert
  end

  # helpers

  defp home_url do
    TransportWeb.Endpoint.url
  end

  defp shortlist_url do
    Path.join(TransportWeb.Endpoint.url,
        TransportWeb.Router.Helpers.page_path(TransportWeb.Endpoint, :shortlist)
    )
  end
end
