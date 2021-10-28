defmodule GBFS.PageCacheTest do
  # NOTE: this test will be polluted by other controller tests since it touches the same cache.
  # We set async to false to avoid that.
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  import Mox
  import AppConfigHelper

  setup :verify_on_exit!

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

    url = "/gbfs/rouen/station_information.json"

    Transport.HTTPoison.Mock |> expect(:get, 1, fn _url -> {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}} end)

    # first call must result in call to third party
    run_query(conn, url)

    # a cache entry must have been created, with proper expiry time
    cache_key = PageCache.build_cache_key(url)
    assert Cachex.get!(:gbfs, cache_key) != nil
    assert_in_delta Cachex.ttl!(:gbfs, cache_key), 30_000, 200

    # second call must not result into call to third party
    Transport.HTTPoison.Mock |> expect(:get, 0, fn _url -> nil end)
    run_query(conn, url)

    # fake time passed, which normally results in expiry
    Cachex.del!(:gbfs, cache_key)

    # last call must again result in call to third party
    Transport.HTTPoison.Mock |> expect(:get, 1, fn _url -> {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}} end)

    run_query(conn, url)
  end

  test "mirrors non-200 status code", %{conn: conn} do
    enable_cache()

    url = "/gbfs/toulouse/station_information.json"

    Transport.HTTPoison.Mock |> expect(:get, 1, fn _url -> {:ok, %HTTPoison.Response{status_code: 500}} end)

    # first call must result in call to third party
    r = conn |> get(url)
    # an underlying 500 will result of a 502
    assert r.status == 502

    # Even if it's an error, a cache entry must have been created, with proper expiry time
    # The resoning behind this is that we don't want to flood the GBFS productor, even if the system is in error
    cache_key = PageCache.build_cache_key(url)
    assert Cachex.get!(:gbfs, cache_key) != nil
    assert_in_delta Cachex.ttl!(:gbfs, cache_key), 30_000, 200

    # Second call must not result into call to third party
    # This is verified by the Mox/expect definition to
    # be called only once.
    r = conn |> get(url)
    assert r.status == 502
  end

  # To be implemented later, but for now the error handling on that (Sentry etc)
  # is not clear (#1378)
  @tag :pending
  test "does not cache anything if we raise an exception"
end
