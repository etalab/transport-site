defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Router.Helpers, only: [static_path: 2]
  require Logger

  def mount(_params, _session, socket) do
    {:ok, socket |> get_some_test_config_in_there}
  end

  def get_some_test_config_in_there(socket) do
    # temporary code used to feed something in there
    config = Application.fetch_env!(:unlock, :config_fetcher).fetch_config!() |> Map.values()
    config = Enum.filter(config, fn x -> %Unlock.Config.Item.SIRI{} = x end)

    base_url = TransportWeb.Backoffice.ProxyConfigLive.proxy_base_url(socket)
    # TODO: create a double list from both proxied & non proxied elements, setting the requestor_ref automatically
    # TODO: do not fill anything unless we have a "transport" member
    config =
      config
      |> Enum.map(fn item ->
        %{
          endpoint_url: TransportWeb.Backoffice.ProxyConfigLive.get_proxy_resource_url(base_url, item.identifier)
        }
      end)

    urls = config |> Enum.map(& &1.endpoint_url)

    socket
    |> assign(:endpoint_url, urls |> List.first())
    |> assign(:endpoint_urls, urls)
    |> assign(:requestor_ref, Application.fetch_env!(:unlock, :siri_public_requestor_ref))
  end

  def handle_event("change_form", params, socket) do
    socket =
      socket
      |> assign(:requestor_ref, params["config"]["requestor_ref"])
      |> assign(:endpoint_url, params["config"]["endpoint_url"])

    {:noreply, socket}
  end

  def handle_event("generate_query", _params, socket) do
    socket =
      socket
      |> assign(:siri_query, generate_query("check_status", socket.assigns[:requestor_ref]))

    {:noreply, socket}
  end

  def handle_event("execute_query", _params, socket) do
    query = socket.assigns[:siri_query]
    IO.puts(query)
    {:noreply, socket}
  end

  # TODO: instead of using the string-based XML generation, use the safer "builder-based" approach,
  # and keep our string-based XMLs as test fixtures to lock down the builder behaviour.
  defp generate_query("check_status", requestor_ref) do
    # must conform to https://www.w3.org/TR/xmlschema-2/#dateTime
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    requestor_ref = requestor_ref
    Transport.SIRI.check_status(timestamp, message_id, requestor_ref)
  end
end
