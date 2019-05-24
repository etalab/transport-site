defmodule TransportWeb.API.AomView do
  alias TransportWeb.API.JSONView

  def render(conn, %{data: data}) do
    JSONView.render(conn, %{data: data})
  end

  def render(conn, %{features: features}) do
    geojson = %{
      "type" => "FeatureCollection",
      "features" => features
    }

    render(conn, %{data: geojson})
  end
end
