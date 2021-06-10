defmodule Unlock.ControllerTest do
  # async false until we stub Cachex calls or use per-test cache name
  use ExUnit.Case, async: false
  use Plug.Test
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint

  import Mox
  setup :verify_on_exit!

  # TODO: persist config in DB for reliability during GitHub outages

  test "GET /" do
    output =
      build_conn()
      |> get("/")
      |> text_response(200)

    assert output == "Unlock Proxy"
  end

  def setup_proxy_config(config) do
    Unlock.Config.Fetcher.Mock
    |> stub(:fetch_config!, fn -> config end)
  end

  describe "GET /resource/:slug" do
    test "handles a regular read" do
      slug = "an-existing-identifier"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item{
          identifier: slug,
          target_url: target_url = "http://localhost/some-remote-resource",
          ttl: 30
        }
      })

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn url, _headers = [] ->
        assert url == target_url

        %Unlock.HTTP.Response{
          body: "somebody-to-love",
          status: 207,
          headers: [
            {"content-type", "application/json"},
            {"content-length", "7350"},
            {"date", "Thu, 10 Jun 2021 19:45:14 GMT"},
            # unwanted headers
            {"x-amzn-request-id", "11111111-2222-3333-4444-f4c5846f0a85"},
            {"x-cache", "Miss from cloudfront"}
          ]
        }
      end)

      resp =
        build_conn()
        |> get("/resource/an-existing-identifier")

      assert resp.resp_body == "somebody-to-love"
      assert resp.status == 207

      # these ones are added by our pipeline for now
      assert Plug.Conn.get_resp_header(resp, "x-request-id")
      # we'll provide a finer grained algorithm later if useful, for now assume no cache is done
      assert Plug.Conn.get_resp_header(resp, "cache-control") == [
               "max-age=0, private, must-revalidate"
             ]

      remaining_headers =
        resp.resp_headers
        |> Enum.reject(fn {h, v} -> Enum.member?(["x-request-id", "cache-control"], h) end)

      assert remaining_headers == [
               {"content-type", "application/json"},
               {"content-length", "7350"},
               {"date", "Thu, 10 Jun 2021 19:45:14 GMT"}
             ]
    end

    test "handles 404"
    test "handles caching"
    test "supports reloading"
    test "handles remote error"
    test "handles proxy error"
  end
end
