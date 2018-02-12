defmodule TransportWeb.API.DatasetView do
  alias TransportWeb.API.DatasetSerializer
  alias TransportWeb.API.JSONView

  def render(_conn, %{data: data}) do
    JaSerializer.format(DatasetSerializer, data)
  end

  def render(conn, %{errors: errors}) do
    JSONView.render(conn, %{errors: errors})
  end
end
