defmodule TransportWeb.API.JSONView do
  def render(_conn, %{data: data}) do
    data
  end

  def render(_conn, %{errors: errors}) do
    errors
  end
end
