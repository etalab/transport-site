defmodule PageCache do
  import Plug.Conn
  require Logger

  def init(options) do
    ttl_seconds = options |> Keyword.get(:ttl_seconds)
    options |> Keyword.put(:ttl, :timer.seconds(ttl_seconds))
  end

  defmodule CacheEntry do
    defstruct [:body, :content_type]
  end

  def build_cache_key(request_path) do
    ["page", request_path] |> Enum.join(":")
  end

  def call(conn, options) do
    page_cache_key = build_cache_key(conn.request_path)

    Cachex.get(options[:cache_name], page_cache_key)
    |> case do
      {:ok, nil} -> handle_miss(conn, page_cache_key, options)
      {:ok, value} -> handle_hit(conn, page_cache_key, value)
      {:error, error} -> handle_error(conn, error)
    end
  end

  def handle_miss(conn, page_cache_key, options) do
    Logger.info("Cache miss for key #{page_cache_key}")

    conn
    |> register_before_send(&save_to_cache/1)
    |> assign(:page_cache_key, page_cache_key)
  end

  def handle_hit(conn, page_cache_key, value) do
    Logger.info("Cache hit for key #{page_cache_key}")

    conn
    # NOTE: not using put_resp_content_type because we would have to split on ";" for charset
    |> put_resp_header("content-type", value.content_type)
    |> send_resp(:ok, value.body)
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

    value = %CacheEntry{
      body: conn.resp_body,
      content_type: conn |> get_resp_header("content-type") |> Enum.at(0)
    }

    Cachex.put(:gbfs, page_cache_key, value, ttl: :timer.seconds(60))
    conn
  end
end
