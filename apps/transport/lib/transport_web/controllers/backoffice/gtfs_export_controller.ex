defmodule TransportWeb.Backoffice.GTFSExportController do
  use TransportWeb, :controller
  require Logger

  def export(%Plug.Conn{} = conn, _params) do
    data_import_ids = Transport.GTFSExportStops.data_import_ids()
    csv_data = Transport.GTFSExportStops.export_stops_report(data_import_ids)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"export.csv\"")
    |> put_root_layout(false)
    |> send_resp(200, csv_data)
  end
end
