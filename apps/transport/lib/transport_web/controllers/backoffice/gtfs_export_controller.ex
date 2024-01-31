defmodule TransportWeb.Backoffice.GTFSExportController do
  use TransportWeb, :controller
  require Logger

  def export(%Plug.Conn{} = conn, _params) do
    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"gtfs_stops_france_export_#{Date.utc_today() |> Date.to_iso8601()}.csv\""
      )
      |> send_chunked(:ok)

    [Transport.GTFSExportStops.export_headers()]
    |> send_csv_data_chunk(conn)

    Transport.GTFSExportStops.data_import_ids()
    |> Enum.chunk_every(25)
    |> Enum.each(fn ids ->
      ids
      |> Transport.GTFSExportStops.export_stops_report()
      |> send_csv_data_chunk(conn)
    end)

    conn
  end

  def send_csv_data_chunk(data, conn) do
    chunk(conn, data |> NimbleCSV.RFC4180.dump_to_iodata())
  end
end
