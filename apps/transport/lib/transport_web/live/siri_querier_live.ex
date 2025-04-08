defmodule TransportWeb.Live.SIRIQuerierLive do
  use Phoenix.LiveView
  use Phoenix.HTML, only: [text_input: 2]
  import Transport.Http.Utils, only: [reencode_body_to_utf8: 2]
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.Router.Helpers, only: [live_path: 3, static_path: 2]
  import Unlock.GunzipTools, only: [maybe_gunzip: 2, lowercase_headers: 1]

  require Logger

  @request_headers [{"content-type", "text/xml"}]
  @supported_url_parameters [
    :endpoint_url,
    :requestor_ref,
    :query_template,
    :stop_ref,
    :line_refs
  ]
  @default_query_template "CheckStatus"
  @supported_query_templates [
    @default_query_template,
    "LinesDiscovery",
    "StopPointsDiscovery",
    "GetEstimatedTimetable",
    "GetGeneralMessage",
    "GetStopMonitoring"
  ]

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)
    {:ok, socket |> assign(base_assigns())}
  end

  def base_assigns do
    %{
      siri_request_headers: @request_headers,
      siri_query: nil,
      siri_response_status_code: nil,
      siri_response_error: nil,
      query_template: @default_query_template,
      query_template_choices: @supported_query_templates,
      line_refs: "",
      stop_ref: ""
    }
  end

  @doc """
  Given a map with string keys, extract a map with atom keys with only the supported parameters.
  """
  def extract_allowed_parameters(params) do
    output = Map.new(@supported_url_parameters, fn p -> {p, params[Atom.to_string(p)]} end)
    # allow-list for QueryTemplate
    if output[:query_template] in @supported_query_templates do
      output
    else
      output |> Map.replace!(:query_template, @default_query_template)
    end
  end

  # called at mount to hydrate our assigns based on supported url parameters
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(extract_allowed_parameters(params))}
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
      case client.post(
             socket.assigns[:endpoint_url],
             socket.assigns[:siri_query],
             @request_headers,
             recv_timeout: 5_000
           ) do
        {:ok, %HTTPoison.Response{} = response} ->
          # LiveView does not allow binary payloads. We can work-around that by using Base64, or using a custom channel.
          # Unzip and reencode the response body if needed.
          # We do not make any attempt to modify the XML prolog
          # (e.g. `<?xml version="1.0" encoding="UTF-8"?>`) to match the target encoding.
          # If the prolog is sent on some payloads, we may need to "string replace"
          # that part too.
          headers = lowercase_headers(response.headers)
          response_body = response.body |> maybe_gunzip(headers) |> reencode_body_to_utf8(headers)

          socket
          |> assign(%{
            siri_response_error: nil,
            siri_response_body: response_body,
            siri_response_status_code: response.status_code,
            siri_response_headers: response.headers
          })

        {:error, %HTTPoison.Error{reason: reason}} ->
          socket |> assign(siri_response_error: inspect(reason), siri_response_status_code: nil)
      end

    {:noreply, socket}
  end

  def handle_event("change_form", params, socket) do
    socket =
      socket
      |> assign(extract_allowed_parameters(params["config"]))

    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  @doc """
  Recreate a proper url with all supported parameters, and tell LiveView
  to set it in the browser, in order to make it easy to copy-paste the current state.
  """
  def self_path(socket) do
    params =
      Enum.reduce(@supported_url_parameters, [], fn param, acc ->
        value = socket.assigns[param]
        # NOTE: not using Keyword functions because they do not guarantee
        # order, and it makes the `assert_patched` test brittle at the moment
        if value in ["", nil], do: acc, else: acc ++ [{param, value}]
      end)

    live_path(socket, __MODULE__, params)
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
