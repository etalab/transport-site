defmodule TransportWeb.API.DatasetView do
  alias TransportWeb.API.DatasetSerializer

  def render("index.jsonapi", %{data: data}) do
    JaSerializer.format(DatasetSerializer, data)
  end
end
