defmodule TransportWeb.GeojsonConversionController do
  use TransportWeb, :controller


  def index(%Plug.Conn{} = conn, _) do
    conn |> render("index.html")
  end

  def convert(%Plug.Conn{} = conn, %{"upload" => upload_params}) do
    file_path = upload_params["file"].path

    conn =
      case call_geojson_converter(file_path) do
        {:ok, res} ->
          conn
          |> Plug.Conn.resp(200, res)
        {:error, err_msg} -> conn |> Plug.Conn.resp(400, err_msg)
      end

    conn
    |> Plug.Conn.send_resp()
  end

  def call_geojson_converter(file_path) do
    case Rambo.run("gtfs-geojson", ["--input", file_path]) do
      {:ok, %Rambo{out: res}} -> {:ok, res}
      {:error, %Rambo{err: err_msg}} -> {:error, err_msg}
      {:error, _} = r -> r
    end
  end
end
