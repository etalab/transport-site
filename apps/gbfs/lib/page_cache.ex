defmodule PageCache do
  @moduledoc """
  This module provides the ability to cache a HTTP response (in RAM, currently using Cachex).

  It is implemented as a Plug, so that you can plug it in any given router.

  In case of technical error (e.g. cache not available), the query should still be honored,
  but without caching.

  Improvements that would make sense:
  - let the caller build the cache key
  - let the caller decide when not to cache, or specify dynamic ttl
  - let the caller handle errors
  """

  # For now we use an allowlist which we can expand.
  # Make sure to avoid including "hop-by-hop" headers here.
  # See https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-p1-messaging-14#section-7.1.3
  # https://www.mnot.net/blog/2011/07/11/what_proxies_must_do
  @forwarded_headers_allowlist [
    "access-control-allow-credentials",
    "access-control-allow-origin",
    "access-control-expose-headers",
    "content-type",
    "content-length",
    "date",
    "last-modified",
    "etag",
    "location"
  ]

  import Plug.Conn
  require Logger

  def init(options), do: options

  defmodule CacheEntry do
    @moduledoc """
    The CacheEntry contains what is serialized in the cache currently.
    """
    defstruct [:body, :headers, :status]
  end

  def build_cache_key(request_path) do
    ["page", request_path] |> Enum.join(":")
  end

  def call(conn, options) do
    page_cache_key = build_cache_key(conn.request_path)

    page_cache_key |> network_name() |> trace_request(:external)

    options
    |> Keyword.fetch!(:cache_name)
    |> Cachex.get(page_cache_key)
    |> case do
      {:ok, nil} -> handle_miss(conn, page_cache_key, options)
      {:ok, value} -> handle_hit(conn, page_cache_key, options, value)
      {:error, error} -> handle_error(conn, error)
    end
  end

  def handle_miss(conn, page_cache_key, options) do
    Logger.info("Cache miss for key #{page_cache_key}")

    page_cache_key |> network_name() |> trace_request(:internal)

    conn
    |> register_before_send(&save_to_cache(&1, options))
    |> assign(:page_cache_key, page_cache_key)
    |> filter_out_headers()
    |> set_cache_control(options)
  end

  def handle_hit(conn, page_cache_key, options, value) do
    Logger.info("Cache hit for key #{page_cache_key}")

    value.headers
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    |> set_cache_control(options)
    |> send_resp(value.status, value.body)
    |> halt
  end

  def set_cache_control(conn, options) do
    conn |> put_resp_header("cache-control", "max-age=#{ttl_seconds(options)}, private, must-revalidate")
  end

  def handle_error(conn, error) do
    Logger.error("Cache failure #{error}")
    Sentry.capture_message("cache_failure", extra: %{url: conn.request_path, error: error})
    # but still honor the request
    conn
  end

  def save_to_cache(conn, options) do
    page_cache_key = conn.assigns.page_cache_key
    Logger.info("Persisting cache key #{page_cache_key} for status #{conn.status}")

    value = %CacheEntry{
      body: conn.resp_body,
      status: conn.status,
      headers: keep_relevant_headers(conn)
    }

    unless page_cache_disabled?() do
      Cachex.put(options |> Keyword.fetch!(:cache_name), page_cache_key, value,
        ttl: :timer.seconds(ttl_seconds(options))
      )
    end

    conn
  end

  def network_name(page_cache_key) do
    case Regex.named_captures(~r|/gbfs/(?<network>.+)/|, page_cache_key) do
      %{"network" => network} -> network
      _ -> nil
    end
  end

  def trace_request(nil, _), do: nil

  def trace_request(network_name, type) do
    unless page_cache_disabled?() do
      GBFS.Telemetry.trace_request(network_name, type)
    end
  end

  @doc """
  Determines if page cache is enabled.

  Page cache is disabled during most tests.
  """
  def page_cache_disabled? do
    Application.get_env(:gbfs, :disable_page_cache, false)
  end

  def ttl_seconds(options) do
    options |> Keyword.fetch!(:ttl_seconds)
  end

  defp filter_out_headers(%Plug.Conn{resp_headers: headers} = conn) do
    headers
    |> Enum.reject(fn {header, _} -> Enum.member?(@forwarded_headers_allowlist, header) end)
    |> Enum.reduce(conn, fn {header, _}, conn -> delete_resp_header(conn, header) end)
  end

  defp keep_relevant_headers(%Plug.Conn{resp_headers: headers}) do
    headers
    |> Enum.map(fn {h, v} -> {String.downcase(h), v} end)
    |> Enum.filter(fn {h, _v} -> Enum.member?(@forwarded_headers_allowlist, h) end)
  end
end
