defmodule TransportWeb.API.PlacesView do
  alias TransportWeb.API.JSONView

  def render(conn, data) do
    JSONView.render(conn, data)
  end
end
