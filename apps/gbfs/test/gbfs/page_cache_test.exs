defmodule GBFS.PageCacheTest do
  # NOTE: this test will be polluted by other controller tests since it touches the same cache.
  # We set async to false to avoid that.
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  import Mock

  def run_query(conn, url) do
    response =
      conn
      |> get(url)

    assert response.status == 200
    assert response.resp_body |> Jason.decode!() |> Map.has_key?("data")

    # NOTE: not using json_response directly because it currently does not catch bogus duplicate "charset"
    assert response |> get_resp_header("content-type") == ["application/json; charset=utf-8"]
  end

  @tag :focus
  test "caches HTTP 200 output", %{conn: conn} do
    # simulate a clean start, otherwise other tests will have filled the cache
    Cachex.clear(:gbfs)

    url = "/gbfs/vlille/station_information.json"

    mock = fn _, _, _ -> {:ok, %HTTPoison.Response{body: "{}", status_code: 200}} end

    # first call must result in call to third party
    with_mock HTTPoison, get: mock do
      run_query(conn, url)
      assert_called_exactly(HTTPoison.get(:_, :_, :_), 1)
    end

    # a cache entry must have been created, with proper expiry time
    cache_key = PageCache.build_cache_key(url)
    assert Cachex.get!(:gbfs, cache_key) != nil
    assert_in_delta Cachex.ttl!(:gbfs, cache_key), 30_000, 200

    # # second call must not result into call to third party
    with_mock HTTPoison, get: mock do
      run_query(conn, url)
      assert_not_called(HTTPoison.get(:_, :_, :_))
    end

    # fake time passed, which normally results in expiry
    Cachex.del!(:gbfs, cache_key)

    # last call must again result in call to third party
    with_mock HTTPoison, get: mock do
      run_query(conn, url)
      assert_called_exactly(HTTPoison.get(:_, :_, :_), 1)
    end
  end

  # The proxy currently does not honor the remote HTTP code (#1379).
  # To be fixed before we implement this test.
  @tag :pending
  test "mirrors non-200 status code"

  # To be implemented later, but for now the error handling on that (Sentry etc)
  # is not clear (#1378)
  @tag :pending
  test "does not cache anything if we raise an exception"
end
