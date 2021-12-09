defmodule Unlock.ControllerTest do
  # async false until we stub Cachex calls or use per-test cache name
  # and also due to our current global mox use
  use ExUnit.Case, async: false
  use Plug.Test
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint

  import Mox
  setup :verify_on_exit!
  # require for current cachex use (out of process)
  setup :set_mox_from_context

  setup do
    setup_telemetry_handler()
    :ok
  end

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

      ttl_in_seconds = 30

      setup_proxy_config(%{
        slug => %Unlock.Config.Item{
          identifier: slug,
          target_url: target_url = "http://localhost/some-remote-resource",
          ttl: ttl_in_seconds
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

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{}, %{target: "proxy:an-existing-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :external], %{}, %{target: "proxy:an-existing-identifier"}}

      # these ones are added by our pipeline for now
      assert Plug.Conn.get_resp_header(resp, "x-request-id")
      # we'll provide a finer grained algorithm later if useful, for now assume no cache is done
      assert Plug.Conn.get_resp_header(resp, "cache-control") == [
               "max-age=0, private, must-revalidate"
             ]

      # we enforce downloads for now, even if this results sometimes in incorrect filenames
      # due to incorrect content-type headers from the remote
      assert Plug.Conn.get_resp_header(resp, "content-disposition") == ["attachment"]

      our_headers = ["x-request-id", "cache-control", "content-disposition"]

      remaining_headers =
        resp.resp_headers
        |> Enum.reject(fn {h, _v} -> Enum.member?(our_headers, h) end)

      assert remaining_headers == [
               {"content-type", "application/json"},
               {"content-length", "7350"},
               {"date", "Thu, 10 Jun 2021 19:45:14 GMT"}
             ]

      verify!(Unlock.HTTP.Client.Mock)

      # subsequent queries should work based on cache
      Unlock.HTTP.Client.Mock
      |> expect(:get!, 0, fn _url, _headers -> nil end)

      {:ok, ttl} = Cachex.ttl(Unlock.Cachex, "resource:an-existing-identifier")
      assert_in_delta ttl / 1000.0, ttl_in_seconds, 1

      resp =
        build_conn()
        |> get("/resource/an-existing-identifier")

      assert resp.resp_body == "somebody-to-love"
      assert resp.status == 207

      assert_received {:telemetry_event, [:proxy, :request, :external], %{}, %{target: "proxy:an-existing-identifier"}}

      refute_received {:telemetry_event, [:proxy, :request, :internal], %{}, %{target: "proxy:an-existing-identifier"}}

      # NOTE: this whole test will have to be DRYed
      remaining_headers =
        resp.resp_headers
        |> Enum.reject(fn {h, _v} -> Enum.member?(our_headers, h) end)

      assert remaining_headers == [
               {"content-type", "application/json"},
               {"content-length", "7350"},
               {"date", "Thu, 10 Jun 2021 19:45:14 GMT"}
             ]

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "handles 404" do
      # such empty
      setup_proxy_config(%{})

      resp =
        build_conn()
        |> get("/resource/unknown")

      assert resp.resp_body == "Not Found"
      assert resp.status == 404
    end

    test "handles optional hardcoded request headers" do
      setup_proxy_config(%{
        "some-identifier" => %Unlock.Config.Item{
          identifier: "some-identifier",
          target_url: "http://localhost/some-remote-resource",
          ttl: 10,
          request_headers: [
            {"SomeHeader", "SomeValue"}
          ]
        }
      })

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn _url, request_headers ->
        # The important assertion is here!
        assert request_headers == [{"SomeHeader", "SomeValue"}]

        # but I'll also use the body to ensure
        %Unlock.HTTP.Response{body: request_headers |> inspect, status: 200, headers: []}
      end)

      resp =
        build_conn()
        |> get("/resource/some-identifier")

      assert resp.resp_body == ~s([{"SomeHeader", "SomeValue"}])
      assert resp.status == 200

      verify!(Unlock.HTTP.Client.Mock)
    end

    @tag :skip
    test "handles remote error"

    @tag :skip
    test "handles proxy error"

    @tag :skip
    test "times out without locking the whole thing"
  end

  defp setup_telemetry_handler do
    event_prefix = Transport.Telemetry.proxy_request_event_names() |> Enum.at(1)
    event_prefix |> :telemetry.list_handlers() |> Enum.map(& &1.id) |> Enum.each(&:telemetry.detach/1)

    test_pid = self()
    # inspired by https://github.com/dashbitco/broadway/blob/main/test/broadway_test.exs
    :telemetry.attach_many(
      "test-handler-#{System.unique_integer()}",
      Transport.Telemetry.proxy_request_event_names(),
      fn name, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end
end
