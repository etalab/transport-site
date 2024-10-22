defmodule TransportWeb.API.Plugs.Auth do
  @moduledoc """
  A very simple plug handling authorization for HTTP requests through tokens.
  It gets the list of (client, token) from the `API_AUTH_CLIENTS` environment variable.

  If the request is authorized, the plug adds the client name to the conn assigns for further use.
  Otherwise, a 401 response is sent.
  """
  import Plug.Conn

  def init(default), do: default

  def call(%Plug.Conn{} = conn, _) do
    case find_client(get_req_header(conn, "authorization")) do
      {:ok, client} ->
        conn |> assign(:client, client)

      :error ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "You must set a valid Authorization header"})
        |> halt()
    end
  end

  defp find_client([authorization]) do
    # Expected format: `client1:secret_token;client2:other_token`
    Application.fetch_env!(:transport, :api_auth_clients)
    |> String.split(";")
    |> Enum.map(&(&1 |> String.split(":") |> List.to_tuple()))
    |> Enum.find_value(:error, fn {client, secret} ->
      if Plug.Crypto.secure_compare(authorization, secret) do
        {:ok, client}
      end
    end)
  end

  defp find_client(_), do: :error
end
