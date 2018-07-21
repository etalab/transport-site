defmodule TransportWeb.API.StatsView do
  alias TransportWeb.API.JSONView

  def render(conn, %{data: geojson}) do
    JSONView.render(conn, %{data: geojson})
  end
end
