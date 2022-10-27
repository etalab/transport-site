defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Gettext
  import TransportWeb.Router.Helpers, only: [live_path: 3, static_path: 2]
  import Unlock.GunzipTools, only: [maybe_gunzip: 2, lowercase_headers: 1]

  require Logger

  @request_headers [{"content-type", "text/xml"}]

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)
    socket = socket |> prepare_initial_assigns()

    {:ok, socket}
  end

  def prepare_initial_assigns(socket) do
    socket
    |> assign(default_params(socket))
    |> assign(:siri_request_headers, @request_headers)
    |> assign(:siri_query, nil)
    |> assign(:siri_response_status_code, nil)
    |> assign(:siri_response_error, nil)
    |> assign(:query_template, "CheckStatus")
    |> assign(:query_template_choices, ["CheckStatus", "LinesDiscovery", "StopPointsDiscovery"])
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       Map.merge(
         %{
           endpoint_url: params["endpoint_url"],
           requestor_ref: socket.assigns[:requestor_ref] || params["requestor_ref"]
         },
         default_params(socket)
       )
     )}
  end

  defp default_params(socket) do
    if Mix.env() == :dev do
      %{
        endpoint_url: socket.assigns[:endpoint_url] || get_one_siri_proxy_url(socket),
        requestor_ref: socket.assigns[:requestor_ref] || Application.fetch_env!(:unlock, :siri_public_requestor_ref)
      }
    else
      %{}
    end
  end

  def get_one_siri_proxy_url(socket) do
    item =
      Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()
      |> Map.values()
      |> Enum.find(fn
        %Unlock.Config.Item.SIRI{} -> true
        _ -> false
      end)

    socket
    |> Transport.Proxy.base_url()
    |> Transport.Proxy.resource_url(item.identifier)
  end

  def handle_event("ignore", _params, socket), do: {:noreply, socket}

  def handle_event("generate_query", _params, socket) do
    {:noreply,
     socket |> assign(%{siri_query: generate_query(socket), siri_response_status_code: nil, siri_response_error: nil})}
  end

  def handle_event("execute_query", _params, socket) do
    client = Transport.Shared.Wrapper.HTTPoison.impl()
    socket = socket |> assign(:siri_query, generate_query(socket))
    # Improvement opportunity: make sure to set proper limits to avoid DOS?
    socket =
      case client.post(socket.assigns[:endpoint_url], socket.assigns[:siri_query], @request_headers, recv_timeout: 5_000) do
        {:ok, %HTTPoison.Response{} = response} ->
          # LiveView does not allow binary payloads. We can work-around that by using Base64, or using a custom channel.
          # Make sure to unzip!
          response_body = maybe_gunzip(response.body, lowercase_headers(response.headers))

          socket
          |> assign(%{
            siri_response_error: nil,
            siri_response_body: response_body,
            siri_response_status_code: response.status_code,
            siri_response_headers: response.headers
          })

        {:error, %HTTPoison.Error{reason: reason}} ->
          socket |> assign(siri_response_error: reason, siri_response_status_code: nil)
      end

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
