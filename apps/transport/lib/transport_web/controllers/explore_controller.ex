defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller

  def vehicle_positions(conn, _params) do
    conn
    |> assign(:extra_script_tags, [TransportWeb.ExploreView, "_head_script_tags.html"])
    |> assign(:extra_bottom_script_tags, [TransportWeb.ExploreView, "_bottom_script_tags.html"])
    |> render("vehicle_positions.html")
  end
end
