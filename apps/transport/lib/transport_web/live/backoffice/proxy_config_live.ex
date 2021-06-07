defmodule TransportWeb.Backoffice.ProxyConfigLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :hello, "World")}
  end
end
