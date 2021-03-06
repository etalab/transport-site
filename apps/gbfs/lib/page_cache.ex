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

  import Plug.Conn
  require Logger

  def init(options), do: options

  defmodule CacheEntry do
    @moduledoc """
    The CacheEntry contains what is serialized in the cache currently.
    """
    defstruct [:body, :content_type, :status]
  end

  def build_cache_key(request_path) do
    ["page", request_path] |> Enum.join(":")
  end

  def call(conn, options) do
    page_cache_key = build_cache_key(conn.request_path)

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

    conn
    |> register_before_send(&save_to_cache(&1, options))
    |> assign(:page_cache_key, page_cache_key)
    |> set_cache_control(options)
  end

  def handle_hit(conn, page_cache_key, options, value) do
    Logger.info("Cache hit for key #{page_cache_key}")

    conn
    # NOTE: not using put_resp_content_type because we would have to split on ";" for charset
    |> put_resp_header("content-type", value.content_type)
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

    # We will likely want to store status code and more headers shortly.
    value = %CacheEntry{
      body: conn.resp_body,
      content_type: conn |> get_resp_header("content-type") |> Enum.at(0),
      status: conn.status
    }

    Cachex.put(options |> Keyword.fetch!(:cache_name), page_cache_key, value, ttl: :timer.seconds(ttl_seconds(options)))

    conn
  end

  @doc """
  The purpose of this method is to help us set TTL to 0 during most tests, to disable cache for tests.

  A better way (to be implemented in the future) will be to use behaviours and alternate implementations
  (like explained in https://dashbit.co/blog/mocks-and-explicit-contracts), but that will do for now.
  """
  def ttl_seconds(options) do
    ttl_seconds = options |> Keyword.fetch!(:ttl_seconds)
    disable_page_cache = Application.get_env(:gbfs, :disable_page_cache, false)
    if disable_page_cache, do: 0, else: ttl_seconds
  end
end
