defmodule Transport.RuntimeConfig.EmailHost do
  # See https://github.com/etalab/transport-site/issues/2154

  def email_host(endpoint \\ TransportWeb.Endpoint, email_host_name \\ Application.fetch_env!(:transport, :email_host_name)) do
    endpoint.url()
    |> URI.parse()
    |> Map.put(:host, email_host_name)
    # see https://hexdocs.pm/elixir/1.12/URI.html#to_string/1, just in case
    |> Map.put(:authority, nil)
  end
end
