defmodule TransportWeb.GTFSDiffController do
  use TransportWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: {:error, any} | Plug.Conn.t()
  def show(conn, %{"id" => gtfs_diff_id}) do
    gtfs_diff = DB.GTFSDiff |> DB.Repo.get!(gtfs_diff_id)

    conn
    |> assign(:gtfs_diff, gtfs_diff)
    |> render()
  end
end
