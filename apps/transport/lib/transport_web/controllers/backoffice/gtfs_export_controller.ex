defmodule TransportWeb.Backoffice.GTFSExportController do
  use TransportWeb, :controller
  require Logger

  # TODO: use real data
  # TODO: make sure output is streamed/chunked
  # TODO: make sure output is zipped if possible
  # TODO: add test for controller
  def export(%Plug.Conn{} = conn, _params) do
    csv_data = [%{stop_lon: 1.17, stop_lat: -39.6}] |> CSV.encode(headers: true) |> Enum.join("")

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"export.csv\"")
    |> put_root_layout(false)
    |> send_resp(200, csv_data)
  end
end
