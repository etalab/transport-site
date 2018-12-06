defmodule TransportWeb.API.AomView do
  alias TransportWeb.API.JSONView

  def render(conn, %{data: data}) do
    JSONView.render(conn, %{data: data})
  end
end
