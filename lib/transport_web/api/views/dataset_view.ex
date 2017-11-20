defmodule TransportWeb.API.DatasetView do
  alias TransportWeb.API.DatasetSerializer

  def render(_conn, %{data: data}) do
    JaSerializer.format(DatasetSerializer, data)
  end
end
