defmodule TransportWeb.Backoffice.ProxyConfigLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~L"HELLO <%= assigns[:hello] %>"
  end

  def mount(_params, _truc, socket) do
    {:ok, assign(socket, :hello, "World")}
  end
end
