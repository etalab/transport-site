defmodule TransportWeb.GTFSDiffController do
  use TransportWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: {:error, any} | Plug.Conn.t()
  def show(conn, %{"id" => gtfs_diff_id}) do
    %{result_url: result_url} = DB.GTFSDiff |> DB.Repo.get!(gtfs_diff_id)

    conn
    |> assign(:result_url, result_url)
    |> render()
  end
end
