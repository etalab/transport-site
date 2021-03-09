defmodule Proxy.Controller do
  use Phoenix.Controller
  import Plug.Conn

  def get(conn, params) do
    case params do
      %{"url" => url} ->
        # TODO: whitelist allowed hosts via configuration
        # TODO: support hidden HTTPS stuff (slug-to-http api key)
        file = FTPDownloader.download(url)
        name = Path.basename(file)

        conn
        |> put_resp_header("Content-Disposition", "attachment; filename=\"#{name}\"")
        |> put_resp_header("Content-Type", "application/octet-stream")
        |> send_file(200, file)
      %{} ->
        send_resp(conn, 200, "Please provide URL")
      end
  end
end
