defmodule Transport.RuntimeConfig.EmailHost do
  @moduledoc """
  Emails can be sent from various machines (site vs workers), and each machine
  has its own host name. When sending emails with links to the site, though, by
  default the url construction (based on the endpoint settings) will be incorrect
  for our use.

  This module helps ensure one can get a base URI with the correct email host name,
  to be used with `Router.Helpers`.

  See https://github.com/etalab/transport-site/issues/2154 for some historical context.
  """

  def email_host(
        endpoint \\ TransportWeb.Endpoint,
        email_host_name \\ Application.fetch_env!(:transport, :email_host_name)
      ) do
    endpoint.url()
    |> URI.parse()
    |> Map.put(:host, email_host_name)
    # see https://hexdocs.pm/elixir/1.12/URI.html#to_string/1, just in case
    |> Map.put(:authority, nil)
  end
end
