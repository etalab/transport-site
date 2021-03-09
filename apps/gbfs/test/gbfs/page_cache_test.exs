defmodule GBFS.PageCacheTest do
  # NOTE: this test will be polluted by other controller tests since it touches the same cache.
  # We set async to false to avoid that.
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  import Mock
  import AppConfigHelper

  def run_query(conn, url) do
    response =
      conn
      |> get(url)

    assert response.status == 200
    assert response.resp_body |> Jason.decode!() |> Map.has_key?("data")

    # NOTE: not using json_response directly because it currently does not catch bogus duplicate "charset"
    assert response |> get_resp_header("content-type") == ["application/json; charset=utf-8"]
  end

  test "caches HTTP 200 output", %{conn: conn} do
    # during most tests, cache is disabled at runtime to avoid polluting results.
    # in the current case though, we want to avoid that & make sure caching is in effect.
    # I can't put that in a "setup" trivially because nested setups are not supported &
    # the whole thing would need a bit more work.
    enable_cache()

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

  test "mirrors non-200 status code", %{conn: conn} do
    enable_cache()

    url = "/gbfs/toulouse/station_information.json"

    mock = fn _ -> {:ok, %HTTPoison.Response{body: "{}", status_code: 500}} end

    # first call must result in call to third party
    with_mock HTTPoison, get: mock do
      r = conn |> get(url)
      # an underlying 500 will result of a 502
      assert r.status == 502
      assert_called_exactly(HTTPoison.get(:_), 1)
    end

    # Even if it's an error, a cache entry must have been created, with proper expiry time
    # The resoning behind this is that we don't want to flood the GBFS productor, even if the system is in error
    cache_key = PageCache.build_cache_key(url)
    assert Cachex.get!(:gbfs, cache_key) != nil
    assert_in_delta Cachex.ttl!(:gbfs, cache_key), 30_000, 200

    # # second call must not result into call to third party
    with_mock HTTPoison, get: mock do
      r = conn |> get(url)
      assert r.status == 502
      assert_not_called(HTTPoison.get(:_))
    end
  end

  # To be implemented later, but for now the error handling on that (Sentry etc)
  # is not clear (#1378)
  @tag :pending
  test "does not cache anything if we raise an exception"
end
