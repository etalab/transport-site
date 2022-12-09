defmodule TransportWeb.GTFSDiffAddLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub


  def render(assigns) do
    ~H"""
    <span class="gtfs_diff_button" phx-click="add_url">🔃</span>
    """
  end

  def mount(_params, %{"url" => url}, socket) do
    {:ok, assign(socket, :url, url)}
  end

  def handle_event("add_url", _value, socket) do
      PubSub.broadcast(TransportWeb.PubSub, "diff", {"add_url", socket.assigns.url})
    {:noreply, socket}
  end
end
