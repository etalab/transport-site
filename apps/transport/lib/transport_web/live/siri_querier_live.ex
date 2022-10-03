defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Router.Helpers, only: [static_path: 2]
  require Logger

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_event(event, params, socket) do
    Logger.info("Got event #{event |> inspect} with params #{params |> inspect}")
    {:noreply, socket}
  end
end
