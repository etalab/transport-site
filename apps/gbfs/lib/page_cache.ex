defmodule PageCache do
  import Plug.Conn
  require Logger

  def init(default), do: default

  def build_cache_key(request_path) do
    ["page", request_path] |> Enum.join(":")
  end

  def call(conn, _default) do
    page_cache_key = build_cache_key(conn.request_path)

    Cachex.get(:gbfs, page_cache_key)
    |> case do
      {:ok, nil} -> handle_miss(conn, page_cache_key)
      {:ok, value} -> handle_hit(conn, page_cache_key, value)
      {:error, error} -> handle_error(conn, error)
    end
  end

  def handle_miss(conn, page_cache_key) do
    Logger.info("Cache miss for key #{page_cache_key}")

    conn
    |> register_before_send(&save_to_cache/1)
    |> assign(:page_cache_key, page_cache_key)
  end

  def handle_hit(conn, page_cache_key, value) do
    Logger.info("Cache hit for key #{page_cache_key}")

    conn
    |> send_resp(:ok, value)
    |> halt
  end

  def handle_error(conn, error) do
    Logger.error("Cache failure #{error}")
    Sentry.capture_message("cache_failure", extra: %{url: conn.request_path, error: error})
    # but still honor the request
    conn
  end

  def save_to_cache(conn) do
    page_cache_key = conn.assigns.page_cache_key
    Logger.info("Persisting cache key #{page_cache_key}")
    Cachex.put(:gbfs, page_cache_key, conn.resp_body, ttl: :timer.seconds(10))
    conn
  end
end
