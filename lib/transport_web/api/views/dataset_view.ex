defmodule TransportWeb.API.DatasetView do
  alias TransportWeb.API.DatasetSerializer

  def render(_conn, %{data: data}) do
    JaSerializer.format(DatasetSerializer, data)
  end

  def render(_conn, %{errors: errors}) do
    Poison.encode(errors)
  end
end
