defmodule Unlock.ControllerTest do
  # async false until we stub Cachex calls or use per-test cache name
  # and also due to our current global mox use, and capture_log
  use ExUnit.Case, async: false
  use Plug.Test
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint

  import ExUnit.CaptureLog

  import Mox
  setup :verify_on_exit!
  # require for current cachex use (out of process)
  setup :set_mox_from_context

  setup do
    Cachex.clear(Unlock.Cachex)
    setup_telemetry_handler()
  end

  @the_good_requestor_ref "transport-data-gouv-fr"
  @a_bad_requestor_ref "I-can-haz-icecream"

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

  describe "SIRI item support" do
    test "denies GET query" do
      slug = "an-existing-identifier"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.SIRI{
          identifier: slug,
          target_url: "http://localhost/some-remote-resource",
          requestor_ref: "the-secret-ref",
          request_headers: [{"Content-Type", "text/xml; charset=utf-8"}]
        }
      })

      resp =
        build_conn()
        # NOTE: required due to plug testing, not by the actual server
        |> put_req_header("content-type", "application/soap+xml")
        |> get("/resource/#{slug}", "Test")

      assert resp.status == 405
    end

    test "forwards POST query to the remote server" do
      slug = "an-existing-identifier"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.SIRI{
          identifier: slug,
          target_url: target_url = "http://localhost/some-remote-resource",
          requestor_ref: target_requestor_ref = "the-secret-ref",
          request_headers: configured_request_headers = [{"Content-Type", "text/xml; charset=utf-8"}]
        }
      })

      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
      incoming_requestor_ref = @the_good_requestor_ref
      message_id = "Test::Message::#{Ecto.UUID.generate()}"
      stop_ref = "SomeStopRef"

      incoming_query =
        SIRIQueries.siri_query_from_builder(
          timestamp,
          incoming_requestor_ref,
          message_id,
          stop_ref
        )

      # we simulate an incoming payload where the caller did not provide a prolog, to verify
      # later that we always add it with explicit version ourselves (see note below)
      refute incoming_query |> String.contains?("<?xml")

      expected_forwarded_response_headers = [
        {"content-type", "application/soap+xml"},
        {"content-length", "7350"},
        {"date", "Thu, 10 Jun 2021 19:45:14 GMT"}
      ]

      expect(Unlock.HTTP.Client.Mock, :post!, fn remote_url, headers, body_sent_to_remote_server ->
        assert remote_url == target_url
        assert headers == configured_request_headers

        # We have decided to always add the prolog with explicit version
        # when forwarding to the remote server.
        # See https://github.com/etalab/transport-site/pull/2459#discussion_r925613234 for in-depth discussion.
        body_sent_to_remote_server = body_sent_to_remote_server |> IO.iodata_to_binary()

        assert body_sent_to_remote_server |> String.contains?(~s(<?xml version="1.0"))

        assert body_sent_to_remote_server ==
                 SIRIQueries.siri_query_from_builder(
                   timestamp,
                   # requestor_ref must have been changed from the incoming one
                   target_requestor_ref,
                   message_id,
                   stop_ref,
                   # prolog must be there with explicit version
                   version: "1.0"
                 )

        %{
          body: "<Everything></Everything>" |> :zlib.gzip(),
          headers:
            expected_forwarded_response_headers ++
              [
                # some headers we do not want to forward to the client
                {"x-amzn-request-id", "11111111-2222-3333-4444-f4c5846f0a85"},
                {"x-cache", "Miss from cloudfront"},
                # NOTE: testing the edge case where the response is gzipped ;
                # the header should be interpreted and the response decompressed
                {"Content-Encoding", "gzip"}
              ],
          status: 200
        }
      end)

      resp =
        build_conn()
        # NOTE: required due to plug testing, not by the actual server
        |> put_req_header("content-type", "application/soap+xml")
        |> post("/resource/an-existing-identifier", incoming_query)

      assert resp.status == 200
      # unzipped for now
      assert resp.resp_body == "<Everything></Everything>"

      our_headers = [
        "x-request-id",
        "cache-control",
        "content-disposition",
        "access-control-allow-origin",
        "access-control-expose-headers",
        "access-control-allow-credentials"
      ]

      remaining_headers =
        resp.resp_headers
        |> Enum.reject(fn {h, _v} -> Enum.member?(our_headers, h) end)

      assert remaining_headers == expected_forwarded_response_headers
    end

    test "forbids query when incorrect input requestor ref is provided" do
      slug = "an-existing-identifier"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.SIRI{
          identifier: slug,
          target_url: "http://localhost/some-remote-resource",
          requestor_ref: "the-secret-ref",
          request_headers: [{"Content-Type", "text/xml; charset=utf-8"}]
        }
      })

      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
      incoming_requestor_ref = @a_bad_requestor_ref
      message_id = "Test::Message::#{Ecto.UUID.generate()}"
      stop_ref = "SomeStopRef"

      query =
        SIRIQueries.siri_query_from_builder(
          timestamp,
          incoming_requestor_ref,
          message_id,
          stop_ref
        )

      resp =
        build_conn()
        # NOTE: required due to plug testing, not by the actual server
        |> put_req_header("content-type", "application/soap+xml")
        |> post("/resource/an-existing-identifier", query)

      assert resp.status == 403
      assert resp.resp_body == "Forbidden"
    end
  end

  describe "GTFS-RT item support" do
    test "denies POST query" do
      slug = "an-existing-identifier"

      ttl_in_seconds = 30

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GTFS.RT{
          identifier: slug,
          target_url: "http://localhost/some-remote-resource",
          ttl: ttl_in_seconds
        }
      })

      resp =
        build_conn()
        |> post("/resource/#{slug}")

      assert resp.status == 405
    end

    test "handles GET /resource/:slug" do
      slug = "an-existing-identifier"

      ttl_in_seconds = 30

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GTFS.RT{
          identifier: slug,
          target_url: target_url = "http://localhost/some-remote-resource",
          ttl: ttl_in_seconds
        }
      })

      expected_forwarded_response_headers = [
        {"content-type", "application/json"},
        {"content-length", "7350"},
        {"date", "Thu, 10 Jun 2021 19:45:14 GMT"}
      ]

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn url, _headers = [] ->
        assert url == target_url

        %Unlock.HTTP.Response{
          body: "somebody-to-love",
          status: 207,
          headers:
            expected_forwarded_response_headers ++
              [
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

      our_headers = [
        "x-request-id",
        "cache-control",
        "content-disposition",
        "access-control-allow-origin",
        "access-control-expose-headers",
        "access-control-allow-credentials"
      ]

      remaining_headers =
        resp.resp_headers
        |> Enum.reject(fn {h, _v} -> Enum.member?(our_headers, h) end)

      assert remaining_headers == expected_forwarded_response_headers

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

      assert remaining_headers == expected_forwarded_response_headers

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "handles HEAD /resource/:slug" do
      slug = "an-existing-identifier"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GTFS.RT{
          identifier: slug,
          target_url: target_url = "http://localhost/some-remote-resource",
          ttl: 30
        }
      })

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn url, _headers = [] ->
        assert url == target_url

        %Unlock.HTTP.Response{
          body: "OK",
          status: 200,
          headers: []
        }
      end)

      resp =
        build_conn()
        |> head("/resource/an-existing-identifier")

      # head = empty body
      assert resp.resp_body == ""
      assert resp.status == 200
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
        "some-identifier" => %Unlock.Config.Item.GTFS.RT{
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

    test "handles remote error" do
      url = "http://localhost/some-remote-resource"
      identifier = "foo"

      setup_proxy_config(%{
        identifier => %Unlock.Config.Item.GTFS.RT{
          identifier: identifier,
          target_url: url,
          ttl: 10
        }
      })

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn ^url, _request_headers ->
        raise RuntimeError
      end)

      logs =
        capture_log(fn ->
          resp = build_conn() |> get("/resource/#{identifier}")

          # Got an exception, nothing is stored in cache
          assert {:ok, []} == Cachex.keys(Unlock.Cachex)
          assert resp.status == 502
          assert resp.resp_body == "Bad Gateway"
        end)

      assert logs =~ ~r/RuntimeError/

      verify!(Unlock.HTTP.Client.Mock)
    end

    @tag :skip
    test "handles proxy error"

    @tag :skip
    test "times out without locking the whole thing"
  end

  defp setup_telemetry_handler do
    events = Unlock.Telemetry.proxy_request_event_names()

    events
    |> Enum.at(1)
    |> :telemetry.list_handlers()
    |> Enum.map(& &1.id)
    |> Enum.each(&:telemetry.detach/1)

    test_pid = self()
    # inspired by https://github.com/dashbitco/broadway/blob/main/test/broadway_test.exs
    :telemetry.attach_many(
      "test-handler-#{System.unique_integer()}",
      events,
      fn name, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end
end
