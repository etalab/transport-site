defmodule GBFS.PageCachePlugTest do
  # NOTE: temporarily set to false, until it doesn't use with_mock anymore
  use ExUnit.Case, async: false
  use Plug.Test
  import ExUnit.CaptureLog
  import Mock
  import AppConfigHelper

  @cache :page_cache_test

  setup_all do
    Cachex.start(@cache)
    :ok
  end

  setup do
    # during most tests, cache is disabled at runtime to avoid polluting results.
    # in the current case though, we want to avoid that & make sure caching is in effect.
    enable_cache()
    Cachex.clear!(@cache)

    on_exit(fn ->
      Cachex.clear!(@cache)
    end)

    :ok
  end

  def plug_options do
    PageCache.init(cache_name: @cache, ttl_seconds: 60)
  end

  def cache_size do
    {:ok, size} = Cachex.count(@cache)
    size
  end

  def issue_uncached_query(options \\ plug_options()) do
    :get
    |> conn("/some")
    |> PageCache.call(options)
    # NOTE: this will raise if the plug has already sent a response
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(200, "Hello world")
  end

  test "caches output on cache miss" do
    assert cache_size() == 0
    conn = issue_uncached_query()
    assert conn.resp_body == "Hello world"
    assert conn.status == 200
    assert conn |> get_resp_header("content-type") == ["text/plain; charset=utf-8"]
    # we return the same value for max-age rather than a decreasing value, to simplify things for now
    # default plug behaviour is "max-age=0, private, must-revalidate", we just tweak the max-age here
    assert conn |> get_resp_header("cache-control") == ["max-age=60, private, must-revalidate"]
    assert cache_size() == 1

    assert_in_delta Cachex.ttl!(@cache, "page:/some"), 60_000, 200
  end

  test "returns cached output on cache hit" do
    assert cache_size() == 0
    # warm-up the cache
    issue_uncached_query()
    assert cache_size() == 1

    conn =
      :get
      |> conn("/some")
      |> PageCache.call(cache_name: @cache, ttl_seconds: 60)

    # NOTE: we are not sending anything ourselves, the plug should have done it itself
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "Hello world"
    assert conn |> get_resp_header("content-type") == ["text/plain; charset=utf-8"]
    # we return the same value for max-age rather than a decreasing value, to simplify things for now
    assert conn |> get_resp_header("cache-control") == ["max-age=60, private, must-revalidate"]
  end

  test "handles cache failure gracefully to still honor the query" do
    capture_log(fn ->
      with_mock Sentry, capture_message: fn _, _ -> nil end do
        conn = issue_uncached_query(cache_name: :this_cache_does_not_exist)

        assert conn.state == :sent
        assert conn.status == 200
        assert conn.resp_body == "Hello world"
        assert conn |> get_resp_header("content-type") == ["text/plain; charset=utf-8"]
        # We do not use the cache value in that case, so use max-age=0
        assert conn |> get_resp_header("cache-control") == ["max-age=0, private, must-revalidate"]

        # we want to be notified in that case, to investigate
        assert_called_exactly(Sentry.capture_message(:_, :_), 1)
      end
    end)
  end
end
