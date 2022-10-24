defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Router.Helpers, only: [live_path: 3, static_path: 2]
  import Unlock.GunzipTools, only: [maybe_gunzip: 2, lowercase_headers: 1]

  require Logger

  def mount(_params, _session, socket) do
    socket = socket |> prepare_initial_assigns()

    {:ok, socket}
  end

  def prepare_initial_assigns(socket, params \\ %{}) do
    socket =
      if Mix.env() == :dev do
        socket
        |> assign(:endpoint_url, params["endpoint_url"] || get_one_siri_proxy_url(socket))
        |> assign(
          :requestor_ref,
          params["requestor_ref"] || Application.fetch_env!(:unlock, :siri_public_requestor_ref)
        )
      else
        socket
        |> assign(:endpoint_url, params["endpoint_url"])
        |> assign(:requestor_ref, params["requestor_ref"])
      end

    socket
    |> assign(:siri_query, nil)
    |> assign(:siri_response_status_code, nil)
    |> assign(:query_template, "CheckStatus")
    |> assign(:query_template_choices, ["CheckStatus", "LinesDiscovery", "StopPointsDiscovery"])
  end

  def handle_params(params, _uri, socket) do
    {:noreply, prepare_initial_assigns(socket, params)}
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
    {:noreply, socket |> assign(:siri_query, generate_query(socket))}
  end

  # TODO: make sure to set proper limits to avoid DOS ; also use a form of timeout?
  def handle_event("execute_query", _params, socket) do
    client = Transport.Shared.Wrapper.HTTPoison.impl()
    socket = socket |> assign(:siri_query, generate_query(socket))
    response = client.post!(socket.assigns[:endpoint_url], socket.assigns[:siri_query])

    # "LV do not allows binary payloads. We can work-around that by using Base64, or using
    # a custom channel" (comment kept here in case useful later). Make sure to unzip!
    response_body = maybe_gunzip(response.body, lowercase_headers(response.headers))

    socket =
      socket
      |> assign(%{
        siri_response_body: response_body,
        siri_response_status_code: response.status_code,
        siri_response_headers: response.headers
      })

    {:noreply, socket}
  end

  def handle_event("change_form", params, socket) do
    socket =
      socket
      |> assign(:endpoint_url, params["config"]["endpoint_url"])
      |> assign(:requestor_ref, params["config"]["requestor_ref"])
      |> assign(:query_template, params["config"]["query_template"])

    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  def self_path(socket) do
    fields = Map.take(socket.assigns, [:endpoint_url])
    live_path(socket, __MODULE__, fields |> Map.reject(fn {_, v} -> v in ["", nil] end))
  end

  def build_timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
  def build_message_id, do: "Test::Message::#{Ecto.UUID.generate()}"

  # TODO: instead of using the string-based XML generation, use the safer "builder-based" approach,
  # and keep our string-based XMLs as test fixtures to lock down the builder behaviour.
  defp generate_query(%Phoenix.LiveView.Socket{assigns: assigns}) do
    generate_query(assigns[:query_template], assigns[:requestor_ref])
  end

  defp generate_query("CheckStatus", requestor_ref) do
    Transport.SIRI.check_status(build_timestamp(), requestor_ref, build_message_id())
  end

  defp generate_query("StopPointsDiscovery", requestor_ref) do
    Transport.SIRI.stop_points_discovery(build_timestamp(), requestor_ref, build_message_id())
  end

  defp generate_query("LinesDiscovery", requestor_ref) do
    Transport.SIRI.lines_discovery(build_timestamp(), requestor_ref, build_message_id())
  end
end
