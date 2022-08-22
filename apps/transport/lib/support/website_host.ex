defmodule Transport.RuntimeConfig.WebsiteHost do
  @moduledoc """
  URLs can be built from various machines (site vs workers), and each machine
  has its own hostname.

  When sending emails with links to the site, though, by
  default the URL construction (based on the endpoint settings) will be incorrect
  for our use.

  This module helps ensure one can get a base URI with the correct website hostname,
  to be used with `Router.Helpers`.

  See https://github.com/etalab/transport-site/issues/2154 for some historical context.
  """

  def website_host(
        endpoint \\ TransportWeb.Endpoint,
        website_hostname \\ Application.fetch_env!(:transport, :website_hostname)
      ) do
    endpoint.url()
    |> URI.parse()
    |> Map.put(:host, website_hostname)
    # see https://hexdocs.pm/elixir/1.12/URI.html#to_string/1, just in case
    |> Map.put(:authority, nil)
  end
end
