defmodule TransportWeb.API.NotificationsController do
  use TransportWeb, :controller
  alias Plug.Conn

  @spec clear_config_cache(Conn.t(), map()) :: Conn.t()
  def clear_config_cache(conn, _params) do
    authorization = conn.req_headers |> Enum.into(%{}) |> Map.get("authorization")

    expected_token = "token #{secret_token()}"

    case authorization do
      ^expected_token ->
        notifications().clear_config_cache!()
        conn |> send_response(200)

      _ ->
        conn |> send_response(401)
    end
  end

  defp send_response(conn, 200 = status) do
    conn |> put_status(status) |> json(%{message: "OK"})
  end

  defp send_response(conn, 401 = status) do
    conn |> put_status(status) |> json(%{message: "Unauthorized"})
  end

  defp notifications, do: Application.fetch_env!(:transport, :notifications_impl)

  defp secret_token, do: Application.fetch_env!(:transport, :notifications_api_token)
end
