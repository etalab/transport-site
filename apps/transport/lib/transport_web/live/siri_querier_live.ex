defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Router.Helpers, only: [static_path: 2]
  require Logger

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:siri_query, generate_query("check_status"))

    {:ok, socket}
  end

  def handle_event("generate", params, socket) do
    %{"query_template" => template} = params
    {:noreply, socket}
  end

  # TODO: instead of using the string-based XML generation, use the safer "builder-based" approach,
  # and keep our string-based XMLs as test fixtures to lock down the builder behaviour.
  defp generate_query("check_status") do
    # must conform to https://www.w3.org/TR/xmlschema-2/#dateTime
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    requestor_ref = "$$YOUR_REQUESTOR_REF$$"
    Transport.SIRI.check_status(timestamp, message_id, requestor_ref)
  end
end
