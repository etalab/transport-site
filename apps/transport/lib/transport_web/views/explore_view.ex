defmodule TransportWeb.ExploreView do
  use TransportWeb, :view
  import Phoenix.Component

  def render("gtfs_stops_data.json", conn) do
    conn.data
  end
end
