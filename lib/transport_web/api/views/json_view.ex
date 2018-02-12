defmodule TransportWeb.API.JSONView do
  def render(_conn, %{data: data}) do
    case Poison.encode(data) do
      {:ok, body} -> body
      {:error, error} -> error
    end
  end

  def render(_conn, %{errors: errors}) do
    case Poison.encode(errors) do
      {:ok, body} -> body
      {:error, error} -> error
    end
  end
end
