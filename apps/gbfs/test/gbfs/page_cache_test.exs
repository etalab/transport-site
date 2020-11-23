# It would be ultimately better to write standalone tests for this plug (instead of
# testing the whole app like currently done), but with the current coverage, an integration
# test like the one below provides more value.
defmodule GBFS.PageCacheTest do
  # NOTE: until we test in standalone mode (Plug Test), we want to make sure no other
  # test-case runs at the same time, so that we can assert on the cache state.
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  import ExUnit.CaptureLog
  require Logger

  def issue_verified_query_and_capture_logs(conn, url) do
    capture_log(fn ->
      response =
        conn
        |> get(url)

      assert response.status == 200

      # NOTE: not using json_response directly because it currently does not catch bogus duplicate "charset"
      assert response |> get_resp_header("content-type") == ["application/json; charset=utf-8"]
    end)
  end

  test "caches HTTP 200 output", %{conn: conn} do
    # simulate a clean start, otherwise other tests will have filled the cache
    Cachex.clear(:gbfs)

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

  # TODO: fix #1379, and then later decide what to do with caching for non-200 returns.
  # Maybe we should cache them still, but with a shorter expiry time
  @tag :pending
  test "cache non-200 response with a different TTL?", %{conn: conn} do
    url = "/gbfs/vcub/station_status.json"

    use_cassette :stub, url: "~r/opendata.bordeaux-metropole.fr/", status_code: 500 do
      _logs =
        capture_log(fn ->
          response =
            conn
            |> get(url)

          # see https://github.com/etalab/transport-site/issues/1379, this won't pass for now
          # we are currently returning 200 where we should not
          assert response.status == 500
        end)
    end
  end
end
