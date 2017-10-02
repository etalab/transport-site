defmodule TransportWeb.OrganizationsSearchTest do
  @moduledoc """
  When the Transport team direct me to transport.beta.gouv.fr
  I want to be able to search for organizations
  """

  use TransportWeb.ConnCase, async: true
  use Hound.Helpers

  alias TransportWeb.Router.Helpers

  hound_session()

  @tag :integration
  test "I can click somewhere to search organizations" do
    search_url() |> navigate_to
    click({:css, "form > input"})

    find_element(:tag, "input")
    |> input_into_field("paris")
    find_element(:tag, "organization")
    |> find_within_element(:tag, "a")
    |> attribute_value("href")
    |> Kernel.=~("organizations/")
    |> assert
  end

  # helpers

  defp search_url do
    TransportWeb.Endpoint.url
    |> Path.join(Helpers.organizations_path(TransportWeb.Endpoint, :search))
  end
end
