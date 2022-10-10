defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Router.Helpers, only: [static_path: 2]
  require Logger

  def mount(_params, _session, socket) do
    socket = socket |> get_some_test_config_in_there()

    {:ok, socket}
  end

  @doc """
  Temporary code to auto-fill one access point based on proxy config
  """
  def get_some_test_config_in_there(socket) do
    socket
    |> assign(:endpoint_url, get_one_siri_proxy_url(socket))
    |> assign(:requestor_ref, Application.fetch_env!(:unlock, :siri_public_requestor_ref))
    |> assign(:query_template, "CheckStatus")
    |> assign(:query_template_choices, ["CheckStatus", "LinesDiscovery", "StopPointsDiscovery"])
  end

  def get_one_siri_proxy_url(socket) do
    item =
      Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()
      |> Map.values()
      |> Enum.find(fn
        %Unlock.Config.Item.SIRI{} -> true
        _ -> false
      end)

    base_url = TransportWeb.Backoffice.ProxyConfigLive.proxy_base_url(socket)
    TransportWeb.Backoffice.ProxyConfigLive.get_proxy_resource_url(base_url, item.identifier)
  end

  def handle_event("generate_query", _params, socket) do
    socket =
      socket
      |> assign(
        :siri_query,
        generate_query(socket.assigns[:query_template], socket.assigns[:requestor_ref])
      )

    {:noreply, socket}
  end

  def handle_event("change_form", params, socket) do
    socket =
      socket
      |> assign(:endpoint_url, params["config"]["endpoint_url"])
      |> assign(:requestor_ref, params["config"]["requestor_ref"])
      |> assign(:query_template, params["config"]["query_template"])

    {:noreply, socket}
  end

  def build_timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
  def build_message_id, do: "Test::Message::#{Ecto.UUID.generate()}"

  # TODO: instead of using the string-based XML generation, use the safer "builder-based" approach,
  # and keep our string-based XMLs as test fixtures to lock down the builder behaviour.
  defp generate_query("CheckStatus", requestor_ref) do
    Transport.SIRI.check_status(build_timestamp(), build_message_id(), requestor_ref)
  end

  defp generate_query("StopPointsDiscovery", requestor_ref) do
    Transport.SIRI.stop_points_discovery(build_timestamp(), build_message_id(), requestor_ref)
  end

  defp generate_query("LinesDiscovery", requestor_ref) do
    Transport.SIRI.lines_discovery(build_timestamp(), build_message_id(), requestor_ref)
  end
end
