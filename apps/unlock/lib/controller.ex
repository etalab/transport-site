defmodule Unlock.Controller do
  @moduledoc """
  The main controller for proxying, focusing on simplicity and runtime control.

  This currently implements an in-RAM (Cachex) loading of the resource, with a reduced
  set of headers that we will improve over time.

  Future evolutions will very likely support disk caching, compression etc.

  Useful resources for later maintenance:
  - https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
  - https://www.mnot.net/blog/2011/07/11/what_proxies_must_do
  """

  use Phoenix.Controller
  require Logger
  import Unlock.GunzipTools

  @doc """
  A simple index "page", useful to verify that the proxy is up, since it is served
  on a subdomain (`https://proxy.transport.data.gouv.fr`).
  """
  def index(conn, _params) do
    text(conn, "Unlock Proxy")
  end

  @doc """
  The central controller action responsible for serving a given resource.

  Based on the provided slug/id, a look-up is done on the configuration.

  For production environments, the configuration is GitHub-based
  (https://github.com/etalab/transport-proxy-config/blob/master/proxy-config.yml).

  When working locally, the config is loaded from disk (`config/proxy-config.yml`)
  at each request, so that one can tweak it easily when iterating locally.

  Configuration items are strongly typed, such as:
  - `%Unlock.Config.Item.Generic.HTTP{}` for HTTP-provided single GTFS-RT & CSV feeds
  - `%Unlock.Config.Item.Aggregate{}` for multi-HTTP-sources aggregate (dynamic IRVE feed only)
  - `%Unlock.Config.Item.S3{}` for internal-S3-backed single file feeds (CSV or anything really)
  - `%Unlock.Config.Item.SIRI{}` for SIRI proxying (experimental)

  Once the item is found in configuration, different `process_resource` pattern-matching variants
  are doing specific processing, depending on the item type.

  If the corresponding item is not found in the configuration, a standard `404`
  is returned.

  There is a catch-all doing only logging and returning a blank `500` with
  default message, when an unhandled exception is caught.

  ### Metrics handling

  #### "External" queries

  An "external query" is counted when the proxy receives a HTTP query from the outside world
  (hence the name "external"). When it happens, each relevant piece of code here emits an
  `:external` metric telemetry event:

  ```elixir
  Unlock.Telemetry.trace_request(item.identifier, :external)
  ```

  This allows us to count, and report on, the total traffic we are handling, for each proxy item.

  #### "Internal" queries

  When an "external query" occurs, there are two scenarios:
  - the content is not yet, or not anymore, in the cache for the corresponding item:
    in this case, the processing occurs, and we cound an `:internal` query on the same
    identifier, to track down the fact that we are actually querying the server we are
    protecting
  - or the content is already in cache and not expired, in which case we _do not_ emit
    an `:internal` metric event.

  ```elixir
  Unlock.Telemetry.trace_request(item.identifier, :internal)
  ```

  #### Usefulness of the metrics

  Because of this system & the split between `:external` and `:internal`, we are able to
  give insights on how much trafic we are handling in the name of third-parties, and also
  what is the ratio between `:external` and `:internal` queries.

  #### For extra reading on how metrics are stored & managed

  - See `Unlock.Telemetry`
  - And `Transport.Telemetry`
  """
  def fetch(conn, %{"id" => id}) do
    config = Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()

    resource = Map.get(config, id)

    if resource do
      conn
      |> process_resource(resource)
    else
      conn
      |> send_resp(404, "Not Found")
    end
  rescue
    exception ->
      # NOTE: we catch the exception to return a controlled/blank answer in production.
      Logger.error("An exception occurred (#{exception |> inspect}")

      cond do
        # give a bit more context when working in development
        Mix.env() == :dev ->
          Logger.error(Exception.format_stacktrace())

        # in test, it is inconvenient to receive a 500, instead we
        # re-raise to make it easier to do ExUnit assertions & avoid swallowed Mox expectations
        Mix.env() == :test ->
          reraise exception, __STACKTRACE__
      end

      conn
      |> send_resp(500, "Internal Error")
  end

  @doc """
  For `Generic.HTTP` items, hardcoded response headers can be
  provided in the YAML configuration.

  This is especially useful to hardcode the filename as we want,
  and ensure HTTP clients will get the CSV extension, which is
  not in the proxy url.

  ### Example

  ```yml
  - identifier: provider-dynamic-irve
    target_url: XYZ
    type: generic-http
    ttl: 10
    response_headers:
      - ["content-disposition", "attachment; filename=provider-dynamic-irve.csv"]
      - ["content-type", "text/csv"]
  ```
  """
  def override_resp_headers_if_configured(conn, %Unlock.Config.Item.Generic.HTTP{} = item) do
    Enum.reduce(item.response_headers, conn, fn {header, value}, conn ->
      conn
      |> put_resp_header(header |> String.downcase(), value)
    end)
  end

  # this is for HTTP parameters handling
  defp to_nil_or_integer(nil), do: nil
  defp to_nil_or_integer(data), do: String.to_integer(data)
  defp to_boolean(nil), do: false
  defp to_boolean("0"), do: false
  defp to_boolean("1"), do: true

  # `process_resource` variant for aggregated CSV item (dynamic IRVE consolidation).
  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.Aggregate{} = item) do
    Unlock.Telemetry.trace_request(item.identifier, :external)
    # NOTE: required for tests to work, and doesn't hurt in production (idempotent afaik)
    conn = conn |> Plug.Conn.fetch_query_params()

    options = [
      limit_per_source: conn.query_params["limit_per_source"] |> to_nil_or_integer(),
      include_origin: conn.query_params["include_origin"] |> to_boolean()
    ]

    body_response = Unlock.AggregateProcessor.process_resource(item, options)
    send_resp(conn, 200, body_response)
  end

  # `process_resource` variant for `Item.S3` items.
  # leverages `fetch_remote` with pattern matching as well.
  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.S3{} = item) do
    Unlock.Telemetry.trace_request(item.identifier, :external)
    response = fetch_remote(item)

    displayed_filename = Path.basename(item.path)

    conn
    |> put_resp_header("content-disposition", "attachment; filename=#{displayed_filename}")
    |> send_resp(response.status, response.body)
  end

  # `process_resource` variant for generic HTTP (GTFS-RT, single-file CSV) items
  # leverages `fetch_remote` with pattern matching as well.
  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.Generic.HTTP{} = item) do
    Unlock.Telemetry.trace_request(item.identifier, :external)
    response = fetch_remote(item)

    response.headers
    |> prepare_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # For now, we enforce the download. This will result in incorrect filenames
    # if the content-type is incorrect, but is better than nothing.
    |> put_resp_header("content-disposition", "attachment")
    |> override_resp_headers_if_configured(item)
    |> send_resp(response.status, response.body)
  end

  defp process_resource(conn, %Unlock.Config.Item.Generic.HTTP{}), do: send_not_allowed(conn)

  # NOTE: this code is designed for private use for now. I have tracked
  # what is required or useful for public opening later here:
  # https://github.com/etalab/transport-site/issues/2476
  #
  # SIRI support is experimental. For now we are encouraging instead SIRI provider to
  # get their game up and improve their ops & software, so that they can directly handle
  # SIRI loads without the proxy.
  #
  # For SIRI, only `POST` is allowed since this is the protocol.
  #
  # The code analyses the incoming XML payload, & replace the `requestor_ref` (used sometimes
  # as an API key) transparently with the one we have configured.
  #
  defp process_resource(%{method: "POST"} = conn, %Unlock.Config.Item.SIRI{} = item) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

    parsed = Unlock.SIRI.parse_incoming(body)

    {modified_xml, external_requestor_refs} =
      Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref(parsed, item.requestor_ref)

    # NOTE: here we assert both that the requestor ref is what is expected, but also that it
    # is met once only. I am not deduping them at the moment on purpose, maybe we'll do that
    # later based on experience.
    if external_requestor_refs == [Application.fetch_env!(:unlock, :siri_public_requestor_ref)] do
      handle_authorized_siri_call(conn, item, modified_xml)
    else
      send_resp(conn, 403, "Forbidden")
    end
  end

  # Forbid `GET` calls for SIRI, explicitely, since this is not the way to issue a SIRI call.
  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.SIRI{}),
    do: send_not_allowed(conn)

  defp send_not_allowed(conn) do
    conn
    |> send_resp(405, "Method Not Allowed")
  end

  @spec handle_authorized_siri_call(Plug.Conn.t(), Unlock.Config.Item.SIRI.t(), Saxy.XML.element()) :: Plug.Conn.t()
  # The SIRI query is serialized into iodata, then a `POST` query is issued.
  #
  # On completion, we unzip if needed to smooth out implementations, filter response headers,
  # and send back the answer to the client.
  defp handle_authorized_siri_call(conn, %Unlock.Config.Item.SIRI{} = item, xml) do
    body = Saxy.encode_to_iodata!(xml, version: "1.0")

    response = Unlock.HTTP.Client.impl().post!(item.target_url, item.request_headers, body)

    headers = response.headers |> lowercase_headers()

    # NOTE: for now, we unzip systematically. This will make it easier
    # to analyse payloads & later remove sensitive data, even if we
    # re-zip afterwards.
    body = maybe_gunzip(response.body, headers)

    headers
    |> filter_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # No content-disposition as attachment for now
    |> send_resp(response.status, body)
  end

  # A wrapper grouping reused logic for two cases:
  # - `%Unlock.Config.Item.Generic.HTTP{}` (GTFS-RT, external CSV etc)
  # - `%Unlock.Config.Item.S3{}` (internal S3 backend)
  #
  # The `Cachex` logic is mutualized between those two cases.
  #
  # Before querying the remote source, the `internal` query event is emitted
  # to ensure the app takes the "real remote query" into account in the metrics.
  #
  # Processing varies between the two item types, thanks to pattern-matching
  # in `Unlock.CachedFetch`.
  defp fetch_remote(%module{} = item) when module in [Unlock.Config.Item.Generic.HTTP, Unlock.Config.Item.S3] do
    comp_fn = fn _key ->
      Logger.debug("Processing proxy request for identifier #{item.identifier}")

      try do
        Unlock.Telemetry.trace_request(item.identifier, :internal)
        Unlock.CachedFetch.fetch_data(item)
      rescue
        e ->
          # NOTE: if an error occurs around the HTTP query, then
          # we want to track it down and return Bad Gateway
          Logger.error(Exception.format(:error, e, __STACKTRACE__))
          {:ignore, bad_gateway_response()}
      end
    end

    cache_name = Unlock.Shared.cache_name()
    cache_key = Unlock.Shared.cache_key(item.identifier)
    # NOTE: concurrent calls to `fetch` with the same key will result (here)
    # in only one fetching call, which is a nice guarantee (avoid overloading of target)
    outcome = Cachex.fetch(cache_name, cache_key, comp_fn)

    case outcome do
      {:ok, result} ->
        Logger.debug("Proxy response for #{item.identifier} served from cache")
        result

      {:commit, result, _options} ->
        result

      {:ignore, result} ->
        Logger.debug("Cache has been skipped for proxy response")
        result

      {:error, _error} ->
        # NOTE: we'll want to have some monitoring here, but not using Sentry
        # because in case of troubles, we will blow up our quota.
        Logger.error("Error while fetching key #{cache_key}")
        bad_gateway_response()
    end
  end

  defp bad_gateway_response do
    %Unlock.HTTP.Response{status: 502, body: "Bad Gateway", headers: [{"content-type", "text/plain"}]}
  end

  # Inspiration (MIT) here https://github.com/tallarium/reverse_proxy_plug
  defp filter_response_headers(headers) do
    Enum.filter(headers, fn {h, _v} -> Enum.member?(Shared.Proxy.forwarded_headers_allowlist(), h) end)
  end

  # This prepare response headers : we do not forward all response headers
  # from the remote, only an allowed list of them, to avoid leaking sensitive data
  # unknowingly.
  defp prepare_response_headers(headers) do
    headers
    |> lowercase_headers()
    |> filter_response_headers()
  end
end
