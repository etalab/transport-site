defmodule TransportWeb.API.V2.Controller do
  use Phoenix.Controller, namespace: TransportWeb

  @spec resources(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resources(conn, _params) do
    json(conn, %{"hello" => "world"})
  end
end
