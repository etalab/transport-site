defmodule TransportWeb.API.RegionView do
  alias TransportWeb.API.JSONView

  def render(conn, %{data: regions}) do
    JSONView.render(conn, %{data: regions})
  end
end
