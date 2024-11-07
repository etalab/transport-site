defmodule TransportWeb.API.ValidatorsController do
  use TransportWeb, :controller
  require Logger

  @doc """
  Proxies an HTTP request to the GTFS transport validator while logging a message
  with the client calling the validator.

  This is used to keep the GTFS validator private, gather usage and can be used
  to add further metrics, quotas or queues.
  """
  def gtfs_transport(%Plug.Conn{assigns: %{client: client}} = conn, %{"url" => url}) do
    Logger.info("Handling GTFS validation from #{client} for #{url}")

    case Shared.Validation.GtfsValidator.Wrapper.impl().validate_from_url(url) do
      {:ok, body} -> conn |> json(body)
      {:error, error} -> send_error_response(conn, error)
    end
  end

  def gtfs_transport(%Plug.Conn{} = conn, _) do
    send_error_response(conn, "You must include a GTFS URL")
  end

  def send_error_response(%Plug.Conn{} = conn, message) do
    conn |> put_status(:bad_request) |> json(%{error: message})
  end
end
