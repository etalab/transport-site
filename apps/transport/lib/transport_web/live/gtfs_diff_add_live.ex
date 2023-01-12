defmodule TransportWeb.GTFSDiffAddLive do
  use Phoenix.LiveView
  alias Phoenix.PubSub

  def render(assigns) do
    ~H"""
    <span class="gtfs_diff_button" phx-click="add_url">🔃</span>
    """
  end

  def mount(_params, %{"url" => url, "page_id" => page_id, "resource_history_id" => resource_history_id}, socket) do
    socket =
      socket |> assign(:url, url) |> assign(:page_id, page_id) |> assign(:resource_history_id, resource_history_id)

    {:ok, socket}
  end

  def handle_event("add_url", _value, socket) do
    PubSub.broadcast(
      TransportWeb.PubSub,
      "diff",
      {"add_url", %{"url" => socket.assigns.url, "resource_history_id" => socket.assigns.resource_history_id},
       socket.assigns.page_id}
    )

    {:noreply, socket}
  end
end
