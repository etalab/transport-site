defmodule TransportWeb.Live.ForceNeTExConversion do
  use Phoenix.LiveView
  import TransportWeb.Gettext, only: [dgettext: 2]

  def render(assigns) do
    ~H"""
    <button class="button" phx-click="force_conversion">
      <%= if @running do %>
        <%= dgettext("backoffice", "Conversions launched") %>
        ✅
      <% else %>
        <%= dgettext("backoffice", "Refresh NeTEx conversions") %>
      <% end %>
    </button>
    """
  end

  def mount(_params, %{"dataset_id" => dataset_id, "locale" => locale}, socket) do
    Gettext.put_locale(locale)

    new_socket =
      socket
      |> assign(dataset_id: dataset_id)
      |> assign(running: false)

    {:ok, new_socket}
  end

  def handle_event("force_conversion", _value, socket) do
    send(self(), {:force_conversion, socket.assigns.dataset_id})
    socket = socket |> assign(running: true)
    {:noreply, socket}
  end

  def handle_info({:force_conversion, dataset_id}, socket) do
    DB.DataConversion.force_refresh_netex_conversions(dataset_id)
    Process.send_after(self(), :stop_running, 3000)
    {:noreply, socket}
  end

  def handle_info({:stop_running}, socket) do
    {:noreply, socket |> assign(:running, false)}
  end
end
