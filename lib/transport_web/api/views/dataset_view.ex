defmodule TransportWeb.API.DatasetView do
  alias TransportWeb.API.DatasetSerializer

  def render(_conn, %{data: data}) do
    JaSerializer.format(DatasetSerializer, data)
  end

  def render(_conn, %{errors: errors}) do
    case Poison.encode(errors) do
      {:ok, body} -> body
      {:error, error} -> error
    end
  end
end
