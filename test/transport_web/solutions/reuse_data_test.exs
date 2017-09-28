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
  test "I can click somewhere to reuse transport data" do
    home_url() |> navigate_to
    click({:css, "svg > g > path"})

    find_element(:class, "landing-reuse")
    |> attribute_value("href")
    |> Kernel.=~("mailto:contact@transport.beta.gouv.fr")
    |> assert
  end

  # helpers

  defp home_url do
    TransportWeb.Endpoint.url
  end
end
