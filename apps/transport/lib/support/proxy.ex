defmodule Transport.Proxy do
  @moduledoc """
  Module to helper deal with proxy items coming from the Unlock proxy.
  """
  def base_url(conn) do
    conn
    |> TransportWeb.Router.Helpers.url()
    |> String.replace("127.0.0.1", "localhost")
    |> String.replace("://", "://proxy.")
  end

  def resource_url(base_url, slug) do
    Path.join(
      base_url,
      Unlock.Router.Helpers.resource_path(TransportWeb.Endpoint, :fetch, slug)
    )
  end
end
