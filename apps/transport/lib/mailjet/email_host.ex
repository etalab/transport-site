defmodule Transport.RuntimeConfig.EmailHost do
  # See https://github.com/etalab/transport-site/issues/2154

  def email_host(endpoint \\ TransportWeb.Endpoint, email_host_name \\ Application.fetch_env!(:transport, :email_host_name)) do
    endpoint.url()
    |> URI.parse()
    |> URI.merge(%URI{host: email_host_name})
  end
end
