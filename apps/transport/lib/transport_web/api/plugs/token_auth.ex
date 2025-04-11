defmodule TransportWeb.API.Plugs.TokenAuth do
  @moduledoc """
  A plug handling authorization for HTTP requests through tokens stored
  in the database in the `token` table.

  When an `authorization` HTTP header is set:
  - If the request is authorized, the plug adds the token to the conn assigns for further use.
  - Otherwise, respond with a 401 response.

  If the `authorization` HTTP header is not set the request can go through.

  Later we will want to count requests by path/token etc.
  """
  import Plug.Conn

  def init(default), do: default

  def call(%Plug.Conn{} = conn, _) do
    case find_client(get_req_header(conn, "authorization")) do
      {:ok, token} ->
        conn |> assign(:token, token)

      :error ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "You must set a valid Authorization header"})
        |> halt()
    end
  end

  defp find_client([authorization]) do
    case DB.Repo.get_by(DB.Token, secret_hash: authorization) do
      %DB.Token{} = token -> {:ok, token}
      nil -> :error
    end
  end

  defp find_client(_), do: {:ok, nil}
end
