defmodule Unlock.Plugs.TokenAuth do
  @moduledoc """
  A plug handling authorization for HTTP requests through tokens stored
  in the database in the `token` table.

  When a token is passed in the query parameters:
  - If the request is authorized, the plug adds the token to the conn assigns for further use.
  - Otherwise, respond with a 401 response.

  If the request does not contain a token, the request can go through.
  """
  import Plug.Conn

  def init(default), do: default

  def call(%Plug.Conn{} = conn, _) do
    conn = fetch_query_params(conn)

    case find_client(Map.get(conn.query_params, "token")) do
      {:ok, token} ->
        log_request(conn, token)
        conn |> assign(:token, token)

      :error ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "You must set a valid token in the query parameters"})
        |> halt()
    end
  end

  defp find_client(token) when is_binary(token) do
    case DB.Repo.get_by(DB.Token, secret_hash: token) do
      %DB.Token{} = token -> {:ok, token}
      nil -> :error
    end
  end

  defp find_client(_), do: {:ok, nil}

  defp log_request(%Plug.Conn{} = conn, %DB.Token{} = token) do
    if conn.request_path |> String.starts_with?("/resource/") do
      slug = conn.request_path |> String.trim_leading("/resource/")

      Ecto.Changeset.change(%DB.ProxyRequest{}, %{
        time: DateTime.utc_now(),
        token_id: token.id,
        proxy_id: slug
      })
      |> DB.Repo.insert!()
    end
  end

  defp log_request(%Plug.Conn{}, nil), do: :ok
end
