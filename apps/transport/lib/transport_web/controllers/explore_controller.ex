defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller

  def vehicle_positions(conn, _params) do
    conn
    |> render("vehicle_positions.html")
  end
end
