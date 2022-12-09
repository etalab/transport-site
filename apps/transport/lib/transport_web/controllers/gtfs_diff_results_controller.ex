defmodule TransportWeb.GtfsDiffResultsController do
  use TransportWeb, :controller


  @spec details(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def details(%Plug.Conn{} = conn, %{"diff_url" => diff_url}) do
    conn |> assign(:diff_url, diff_url) |> render("details.html")
  end
end
