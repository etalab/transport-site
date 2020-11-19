defmodule GBFS.PageCacheTest do
  use GBFS.ConnCase, async: true
  import ExUnit.CaptureLog
  require Logger

  def issue_verified_query_and_capture_logs(conn, url) do
    capture_log(fn ->
      conn
      |> get(url)
      # note: this asserts that content-type is restored too
      |> json_response(200)
    end)
  end

  test "caches HTTP 200 output", %{conn: conn} do
    url = "/gbfs"
    cache_key = PageCache.build_cache_key(url)

    logs = issue_verified_query_and_capture_logs(conn, url)
    assert logs =~ "Cache miss for key"
    assert logs =~ "Persisting cache key"

    assert Cachex.get!(:gbfs, cache_key) != nil
    assert_in_delta Cachex.ttl!(:gbfs, cache_key), 60_000, 200

    logs = issue_verified_query_and_capture_logs(conn, url)
    assert logs =~ "Cache hit for key"

    # fake time passed, should re-fetch
    Cachex.del!(:gbfs, cache_key)

    logs = issue_verified_query_and_capture_logs(conn, url)
    assert logs =~ "Cache miss for key"
  end
end
