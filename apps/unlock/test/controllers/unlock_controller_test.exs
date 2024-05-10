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
        slug => %Unlock.Config.Item.Generic.HTTP{
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
        slug => %Unlock.Config.Item.Generic.HTTP{
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
        slug => %Unlock.Config.Item.Generic.HTTP{
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
        "some-identifier" => %Unlock.Config.Item.Generic.HTTP{
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

    test "supports override of response headers" do
      setup_proxy_config(%{
        "some-identifier" => %Unlock.Config.Item.Generic.HTTP{
          identifier: "some-identifier",
          target_url: "http://localhost/some-remote-resource",
          ttl: 10,
          response_headers: [
            # upper-case should be converted to lower-case
            {"Content-disposition", "attachment; filename=data.csv"}
          ]
        }
      })

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn _url, _request_headers ->
        %Unlock.HTTP.Response{
          body: "content",
          status: 200,
          headers: [{"content-disposition", "foobar"}]
        }
      end)

      resp =
        build_conn()
        |> get("/resource/some-identifier")

      assert resp.resp_headers |> Enum.filter(fn {k, _v} -> k == "content-disposition" end) ==
               [{"content-disposition", "attachment; filename=data.csv"}]

      assert resp.status == 200

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "handles remote error" do
      url = "http://localhost/some-remote-resource"
      identifier = "foo"

      setup_proxy_config(%{
        identifier => %Unlock.Config.Item.Generic.HTTP{
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

  describe "Aggregate item support" do
    @expected_headers [
      "id_pdc_itinerance",
      "etat_pdc",
      "occupation_pdc",
      "horodatage",
      "etat_prise_type_2",
      "etat_prise_type_combo_ccs",
      "etat_prise_type_chademo",
      "etat_prise_type_ef"
    ]

    # maps are unordered, and in this case the columns
    # MUST be ordered (by spec)
    defmodule Helper do
      def data_as_csv(headers, rows_as_maps, line_separator) do
        rows =
          rows_as_maps
          |> Enum.map(fn row ->
            headers
            |> Enum.map(fn c -> Map.fetch!(row, c) end)
          end)

        # NOTE: not using the csv library to generate csv here on purpose, so that
        # we can actually test the behaviour with a different code path.
        [headers | rows]
        |> Enum.map(fn data -> data |> Enum.join(",") end)
        |> Enum.map_join(fn data -> data <> line_separator end)
      end
    end

    @first_data_row %{
      "id_pdc_itinerance" => "FR123",
      "etat_pdc" => "xyz",
      "occupation_pdc" => "xyz",
      "horodatage" => "xyz",
      "etat_prise_type_2" => "xyz",
      "etat_prise_type_combo_ccs" => "xyz",
      "etat_prise_type_chademo" => "xyz",
      "etat_prise_type_ef" => "xyz"
    }

    @second_data_row %{
      "id_pdc_itinerance" => "FR456",
      "etat_pdc" => "xyz",
      "occupation_pdc" => "xyz",
      "horodatage" => "xyz",
      "etat_prise_type_2" => "xyz",
      "etat_prise_type_combo_ccs" => "xyz",
      "etat_prise_type_chademo" => "xyz",
      "etat_prise_type_ef" => "xyz"
    }

    def setup_aggregate_proxy_config(slug) do
      setup_proxy_config(%{
        slug => %Unlock.Config.Item.Aggregate{
          identifier: slug,
          feeds: [
            %Unlock.Config.Item.Generic.HTTP{
              identifier: "first-remote",
              target_url: url = "http://localhost:1234",
              ttl: 10
            },
            %Unlock.Config.Item.Generic.HTTP{
              identifier: "second-remote",
              target_url: second_url = "http://localhost:5678",
              ttl: 10
            }
          ]
        }
      })

      {url, second_url}
    end

    def setup_remote_responses(responses) do
      # Processing is concurrent and while the output is "ordered" by design, the requests
      # are not guaranteed to come in the right order, so we have to cheat a bit here.
      # We introduce flexibility to ensure whatever target is processed first, N queries are made
      # and the rest (order & content) is tested by the final assertion on response body.
      response_function = fn url, _request_headers ->
        data = Map.fetch!(responses, url)
        {status, body} = if is_function(data), do: data.(), else: data
        %Unlock.HTTP.Response{body: body, status: status, headers: []}
      end

      Unlock.HTTP.Client.Mock
      |> expect(:get!, responses |> Map.keys() |> length(), response_function)
    end

    test "handles GET /resource/:slug" do
      {url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        # On line separators: both "\r\n" (Windows) and "\n" (Linux, generally) can be seen
        url => {200, Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")},
        second_url => {200, Helper.data_as_csv(@expected_headers, [@second_data_row], "\n")}
      })

      resp =
        build_conn()
        |> get("/resource/an-existing-aggregate-identifier")

      assert resp.status == 200
      # Note: TIL: NimbleCSV.RFC4180.dump_to_iodata generates "\r\n" (apparently)
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [@first_data_row, @second_data_row], "\r\n")

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-aggregate-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:first-remote"}}

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:second-remote"}}

      # TODO: add logs assertions

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "drops bogus 200 sub-feed content safely" do
      {url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        url => {200, Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")},
        second_url => {200, Helper.data_as_csv(["foo"], [%{"foo" => "bar"}], "\n")}
      })

      {resp, logs} =
        with_log(fn ->
          build_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      # we consider that the overall response is OK (and will provide observability of bogus feeds elsewhere)
      assert resp.status == 200
      # does not include second (bogus) data, but still includes first (non bogus) data
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")
      refute String.contains?(resp.resp_body, "foo")

      assert logs =~ ~r|Broken stream for origin second-remote \(headers are \["foo"\]\)|

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "drops sub-feed raising exception (e.g. request hard error)" do
      {url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        url => {200, Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")},
        second_url => fn -> raise %Mint.TransportError{reason: :nxdomain} end
      })

      {resp, logs} =
        with_log(fn ->
          build_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      assert resp.status == 200
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")

      assert logs =~ ~r|Non-200 response for origin second-remote, response has been dropped|

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "hides a non-200 feed from the output without polluting 200 feeds" do
      slug = "an-existing-aggregate-identifier"

      {url, second_url} = setup_aggregate_proxy_config(slug)

      setup_remote_responses(%{
        url => {200, Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")},
        second_url => {500, Helper.data_as_csv(@expected_headers, [@second_data_row], "\n")}
      })

      resp =
        build_conn()
        |> get("/resource/an-existing-aggregate-identifier")

      assert resp.status == 200
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [@first_data_row], "\r\n")

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-aggregate-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:first-remote"}}

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:second-remote"}}

      # TODO - assert metric only on bogus feed event (we still want it)
      # TODO - assert logs

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "handles 302 in sub-feed gracefully"
    test "async stream timeout (specific code path)"
    test "limit mode"
    test "source tracing"
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
