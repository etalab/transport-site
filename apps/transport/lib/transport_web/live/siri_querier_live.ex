defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import TransportWeb.Gettext
  import TransportWeb.Router.Helpers, only: [live_path: 3, static_path: 2]
  import Unlock.GunzipTools, only: [maybe_gunzip: 2, lowercase_headers: 1]

  require Logger

  @request_headers [{"content-type", "text/xml"}]

  def mount(params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    socket =
      socket
      |> assign(base_assigns())
      |> maybe_assign(params["endpoint_url"], :endpoint_url)
      |> maybe_assign(params["requestor_ref"], :requestor_ref)
      |> maybe_assign(params["query_template"], :query_template)

    {:ok, socket}
  end

  def maybe_assign(socket, value, assign_key) do
    if value, do: socket |> assign(assign_key, value), else: socket
  end

  def base_assigns() do
    %{
      siri_request_headers: @request_headers,
      siri_query: nil,
      siri_response_status_code: nil,
      siri_response_error: nil,
      query_template: "CheckStatus",
      query_template_choices: [
        "CheckStatus",
        "LinesDiscovery",
        "StopPointsDiscovery",
        "GetEstimatedTimetable",
        "GetGeneralMessage",
        "GetStopMonitoring"
      ],
      line_refs: "",
      stop_ref: ""
    }
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(%{
       endpoint_url: params["endpoint_url"],
       requestor_ref: params["requestor_ref"],
       query_template: params["query_template"]
     })}
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
     socket
     |> assign(%{
       siri_query: generate_query(socket),
       siri_response_status_code: nil,
       siri_response_error: nil
     })}
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
      |> assign(:line_refs, params["config"]["line_refs"])
      |> assign(:stop_ref, params["config"]["stop_ref"])

    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  def self_path(socket) do
    fields = Map.take(socket.assigns, [:endpoint_url, :requestor_ref, :query_template])
    live_path(socket, __MODULE__, fields |> Map.reject(fn {_, v} -> v in ["", nil] end))
  end

  def build_timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
  def build_message_id, do: "Test::Message::#{Ecto.UUID.generate()}"

  defp generate_query(%Phoenix.LiveView.Socket{assigns: assigns}) do
    query_generator = Transport.SIRIQueryGenerator.impl()

    line_refs =
      if assigns[:line_refs] do
        assigns[:line_refs] |> String.split(",") |> Enum.map(&String.trim(&1))
      else
        nil
      end

    stop_ref =
      if assigns[:stop_ref] do
        assigns[:stop_ref] |> String.trim()
      else
        nil
      end

    params = %{
      template: assigns[:query_template],
      requestor_ref: assigns[:requestor_ref],
      message_id: build_message_id(),
      timestamp: build_timestamp(),
      line_refs: line_refs,
      stop_ref: stop_ref
    }

    query_generator.generate_query(params)
  end
end
