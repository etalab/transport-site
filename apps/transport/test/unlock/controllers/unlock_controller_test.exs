defmodule Unlock.ControllerTest do
  # async false until we stub Cachex calls or use per-test cache name
  # and also due to our current global mox use, and capture_log
  use TransportWeb.ConnCase, async: false
  import Plug.Conn

  import ExUnit.CaptureLog

  import Mox
  setup :verify_on_exit!
  # require for current cachex use (out of process)
  setup :set_mox_from_context

  setup do
    Cachex.clear(Unlock.Shared.cache_name())
    setup_telemetry_handler()
  end

  @the_good_requestor_ref "transport-data-gouv-fr"
  @a_bad_requestor_ref "I-can-haz-icecream"

  test "GET /" do
    output =
      proxy_conn()
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
        proxy_conn()
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
        proxy_conn()
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
        proxy_conn()
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
        proxy_conn()
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
      |> expect(:get!, fn url, _headers, _options = [] ->
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
        proxy_conn()
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
      |> expect(:get!, 0, fn _url, _headers, _options -> nil end)

      {:ok, ttl} = Cachex.ttl(Unlock.Shared.cache_name(), "resource:an-existing-identifier")
      assert_in_delta ttl / 1_000, ttl_in_seconds, 1

      resp =
        proxy_conn()
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
      |> expect(:get!, fn url, _headers = [], _options ->
        assert url == target_url

        %Unlock.HTTP.Response{
          body: "OK",
          status: 200,
          headers: []
        }
      end)

      resp =
        proxy_conn()
        |> head("/resource/an-existing-identifier")

      # head = empty body
      assert resp.resp_body == ""
      assert resp.status == 200
    end

    test "handles 404" do
      # such empty
      setup_proxy_config(%{})

      resp =
        proxy_conn()
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
      |> expect(:get!, fn _url, request_headers, _options ->
        # The important assertion is here!
        assert request_headers == [{"SomeHeader", "SomeValue"}]

        # but I'll also use the body to ensure
        %Unlock.HTTP.Response{body: request_headers |> inspect, status: 200, headers: []}
      end)

      resp =
        proxy_conn()
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
      |> expect(:get!, fn _url, _request_headers, _options ->
        %Unlock.HTTP.Response{
          body: "content",
          status: 200,
          headers: [{"content-disposition", "foobar"}]
        }
      end)

      resp =
        proxy_conn()
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
      |> expect(:get!, fn ^url, _request_headers, _options ->
        raise RuntimeError
      end)

      logs =
        capture_log(fn ->
          resp = proxy_conn() |> get("/resource/#{identifier}")

          # Got an exception, nothing is stored in cache
          assert {:ok, []} == Cachex.keys(Unlock.Shared.cache_name())
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

    defmodule Helper do
      @doc """
      Given an ordered list of headers, and rows as maps (which are inherently unordered), build
      a CSV respecting the exact set of headers in the right orders (as `TableSchema` dictates by default)
      """
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

    def build_unique_data_row do
      # Not very respectful of the schema at the moment, but good enough for the tests
      %{
        "id_pdc_itinerance" => "FRA12" <> (Ecto.UUID.generate() |> String.upcase()),
        "etat_pdc" => "xyz",
        "occupation_pdc" => "xyz",
        "horodatage" => "xyz",
        "etat_prise_type_2" => "xyz",
        "etat_prise_type_combo_ccs" => "xyz",
        "etat_prise_type_chademo" => "xyz",
        "etat_prise_type_ef" => "xyz"
      }
    end

    def setup_aggregate_proxy_config(slug) do
      setup_proxy_config(%{
        slug => %Unlock.Config.Item.Aggregate{
          identifier: slug,
          feeds: [
            %Unlock.Config.Item.Generic.HTTP{
              identifier: "first-uuid",
              slug: "first-slug",
              target_url: url = "http://localhost:1234",
              ttl: 10
            },
            %Unlock.Config.Item.Generic.HTTP{
              identifier: "second-uuid",
              slug: "second-slug",
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
      response_function = fn url, _request_headers, _options ->
        data = Map.fetch!(responses, url)
        # allow function to define data
        data = if is_function(data), do: data.(), else: data
        # append optional response headers
        {status, body, headers} = if match?({_a, _b}, data), do: :erlang.append_element(data, []), else: data
        %Unlock.HTTP.Response{body: body, status: status, headers: headers}
      end

      Unlock.HTTP.Client.Mock
      |> expect(:get!, responses |> Map.keys() |> length(), response_function)
    end

    test "handles GET /resource/:slug" do
      {url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        # On line separators: both "\r\n" (Windows) and "\n" (Linux, generally) can be seen
        url => {200, Helper.data_as_csv(@expected_headers, [first_data_row = build_unique_data_row()], "\r\n")},
        second_url => {200, Helper.data_as_csv(@expected_headers, [second_data_row = build_unique_data_row()], "\n")}
      })

      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      assert resp.status == 200
      # Note: TIL: NimbleCSV.RFC4180.dump_to_iodata generates "\r\n" (apparently)
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [first_data_row, second_data_row], "\r\n")
      headers = resp.resp_headers |> Enum.into(%{})
      assert headers["content-disposition"] =~ ~r/^attachment; filename=an-existing-aggregate-identifier-.*\.csv$/

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-aggregate-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:first-uuid"}}

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:second-uuid"}}

      refute_received {:telemetry_event, _, _, _}

      assert logs =~ ~r|first-uuid responded with HTTP code 200|
      assert logs =~ ~r|second-uuid responded with HTTP code 200|

      verify!(Unlock.HTTP.Client.Mock)

      # more calls should not result in any real query
      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      assert resp.status == 200
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [first_data_row, second_data_row], "\r\n")

      assert logs =~ ~r|Proxy response for an-existing-aggregate-identifier:first-uuid served from cache|
      assert logs =~ ~r|Proxy response for an-existing-aggregate-identifier:second-uuid served from cache|

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-aggregate-identifier"}}

      refute_received {:telemetry_event, _, _, _}
    end

    test "drops bogus 200 sub-feed content safely" do
      {first_url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        first_url => {200, Helper.data_as_csv(@expected_headers, [first_data_row = build_unique_data_row()], "\r\n")},
        second_url => {200, Helper.data_as_csv(["foo"], [%{"foo" => "bar"}], "\n")}
      })

      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      # we consider that the overall response is OK (and will provide observability of bogus feeds elsewhere)
      assert resp.status == 200
      # does not include second (bogus) data, but still includes first (non bogus) data
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [first_data_row], "\r\n")
      refute String.contains?(resp.resp_body, "foo")

      assert logs =~ ~r|Broken stream for origin second-slug/second-uuid \(headers are \["foo"\]\)|

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "drops sub-feed raising exception with simulated 502 (e.g. request hard error)" do
      {first_url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        first_url => {200, Helper.data_as_csv(@expected_headers, [first_data_row = build_unique_data_row()], "\r\n")},
        # this is swallowed by the code and interpreted as 502
        second_url => fn -> raise %Mint.TransportError{reason: :nxdomain} end
      })

      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      assert resp.status == 200
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [first_data_row], "\r\n")

      assert logs =~ ~r|Non-200 response for origin second-slug/second-uuid \(status=502\), response has been dropped|

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "hides a non-200 feed from the output without polluting 200 feeds" do
      slug = "an-existing-aggregate-identifier"

      {first_url, second_url} = setup_aggregate_proxy_config(slug)

      setup_remote_responses(%{
        first_url => {200, Helper.data_as_csv(@expected_headers, [first_data_row = build_unique_data_row()], "\r\n")},
        second_url => {500, Helper.data_as_csv(@expected_headers, [second_data_row = build_unique_data_row()], "\n")}
      })

      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      assert resp.status == 200
      # bogus content (500) is left out
      refute String.contains?(resp.resp_body, second_data_row |> Map.fetch!("id_pdc_itinerance"))
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [first_data_row], "\r\n")

      # we still want the event on the bogus remote
      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-aggregate-identifier:second-uuid"}}

      assert logs =~ ~r|Non-200 response for origin second-slug/second-uuid \(status=500\), response has been dropped|

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "passes `max_redirects` option to Finch wrapper" do
      # not very elegant test, giving another hint that it would
      # be a good idea to migrate to `Req` here to leverage
      # its testing facilities ultimately
      slug = "an-existing-aggregate-identifier"
      {first_url, second_url} = setup_aggregate_proxy_config(slug)
      main_pid = self()
      body = Helper.data_as_csv(@expected_headers, [build_unique_data_row()], "\r\n")

      Unlock.HTTP.Client.Mock
      |> expect(:get!, 2, fn a, b, c ->
        # NOTE: we need a messaging trick here because expectations are
        # not properly asserted due to how errors are handled underneath
        send(main_pid, {:query_parameters, a, b, c})
        %Unlock.HTTP.Response{body: body, headers: [], status: 200}
      end)

      proxy_conn()
      |> get("/resource/an-existing-aggregate-identifier")

      # assert that the expected max_redirects count has been passed
      assert_received {:query_parameters, ^first_url, [], [max_redirects: 2]}
      assert_received {:query_parameters, ^second_url, [], [max_redirects: 2]}
    end

    def wait_til_dead(pid) do
      if Process.alive?(pid) do
        :timer.sleep(5)
        wait_til_dead(pid)
      else
        pid
      end
    end

    # NOTE: this test can be simplified if we stop using `Cachex` directly during tests & instead use a Behaviour
    test "drops data safely when meeting async stream timeout" do
      {first_url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      # This is what simulates the timeout (a long duration, longer than the `Task.async_stream` `:timout` parameter).
      # For technical reasons probably caused by the fact that we use global state via Cachex
      # and how Cachex works + timeouts handling in Cachex/mox combination, I ended up avoiding
      # calling `:timer.sleep` directly in the Mox call, otherwise it will make Cachex/Mox unresponsive
      # in **other** tests. I create a dedicated process for that.
      flag_pid = spawn(fn -> :timer.sleep(10_000) end)

      setup_remote_responses(%{
        first_url => {200, Helper.data_as_csv(@expected_headers, [first_data_row = build_unique_data_row()], "\r\n")},
        # second call: wait until the flag process has stopped
        second_url => fn ->
          ref = Process.monitor(flag_pid)

          receive do
            {:DOWN, ^ref, _, _, _} -> nil
          end
        end
      })

      # Lower `Task.async_stream` timeout for this test only, via the process dictionary,
      # so we can trigger it without waiting 5 seconds during each test run.
      # This approach is `async: true` compatible, if we improve the test suite in that direction.
      Process.put(:override_aggregate_processor_async_timeout, 50)

      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-aggregate-identifier")
        end)

      assert resp.status == 200

      # make sure timout is not too aggressive for the 200 feed
      assert logs =~ ~r|first-uuid responded with HTTP code 200|
      assert logs =~ ~r|Timeout for origin second-uuid, response has been dropped|

      # first part must still be there despite the second part timeout
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [first_data_row], "\r\n")

      # finally, kill the flag process so that the Mox call ends up in a cleaner fashion
      Process.exit(flag_pid, :kill)
      wait_til_dead(flag_pid)
      # Empirically, it appears we still need a bit of delay here to avoid
      # polluting other tests with timeouts. Maybe linked to how Cachex mailbox system works.
      :timer.sleep(50)

      verify!(Unlock.HTTP.Client.Mock)
    end

    test "limit mode allows to only get a sample of each source" do
      {first_url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        first_url =>
          {200,
           Helper.data_as_csv(
             @expected_headers,
             [row_one_one = build_unique_data_row(), _row_one_two = build_unique_data_row()],
             "\r\n"
           )},
        second_url =>
          {200,
           Helper.data_as_csv(
             @expected_headers,
             [row_two_one = build_unique_data_row(), _row_two_two = build_unique_data_row()],
             "\n"
           )}
      })

      resp =
        proxy_conn()
        |> get("/resource/an-existing-aggregate-identifier", limit_per_source: 1)

      assert resp.status == 200
      assert resp.resp_body == Helper.data_as_csv(@expected_headers, [row_one_one, row_two_one], "\r\n")
      verify!(Unlock.HTTP.Client.Mock)
    end

    test "source tracing adds one column to identify each remote" do
      {first_url, second_url} = setup_aggregate_proxy_config("an-existing-aggregate-identifier")

      setup_remote_responses(%{
        first_url => {200, Helper.data_as_csv(@expected_headers, [first_data_row = build_unique_data_row()], "\r\n")},
        second_url => {200, Helper.data_as_csv(@expected_headers, [second_data_row = build_unique_data_row()], "\n")}
      })

      resp =
        proxy_conn()
        |> get("/resource/an-existing-aggregate-identifier", include_origin: 1)

      assert resp.status == 200
      expected_headers = @expected_headers ++ ["origin", "slug"]
      first_expected_output_row = first_data_row |> Map.put("origin", "first-uuid") |> Map.put("slug", "first-slug")
      second_expected_output_row = second_data_row |> Map.put("origin", "second-uuid") |> Map.put("slug", "second-slug")

      assert resp.resp_body ==
               Helper.data_as_csv(expected_headers, [first_expected_output_row, second_expected_output_row], "\r\n")

      verify!(Unlock.HTTP.Client.Mock)
    end
  end

  describe "S3 item support" do
    test "handles GET /resource/:slug (success case)" do
      slug = "an-existing-s3-identifier"
      ttl_in_seconds = 30
      bucket_key = "aggregates"
      path = "irve_static_consolidation.csv"
      # automatically built by the app based on `bucket_key`
      expected_bucket = "transport-data-gouv-fr-aggregates-test"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.S3{
          identifier: slug,
          bucket: bucket_key,
          path: path,
          ttl: ttl_in_seconds
        }
      })

      content = "CONTENT"

      Transport.ExAWS.Mock
      |> expect(:request!, fn %ExAws.Operation.S3{} = operation ->
        assert %ExAws.Operation.S3{
                 bucket: ^expected_bucket,
                 path: ^path,
                 http_method: :get,
                 service: :s3
               } = operation

        %{body: content, status_code: 200}
      end)

      resp =
        proxy_conn()
        |> get("/resource/an-existing-s3-identifier")

      assert resp.resp_body == content
      assert resp.status == 200
      # enforce the filename provided via the config (especially to get its extension passed to clients)
      assert Plug.Conn.get_resp_header(resp, "content-disposition") == ["attachment; filename=#{path}"]

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-s3-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-s3-identifier"}}

      verify!(Transport.ExAWS.Mock)
    end

    test "handles GET /resource/:slug (ExAWS failure case)" do
      slug = "an-existing-s3-identifier"
      ttl_in_seconds = 30
      bucket_key = "aggregates"
      path = "irve_static_consolidation.csv"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.S3{
          identifier: slug,
          bucket: bucket_key,
          path: path,
          ttl: ttl_in_seconds
        }
      })

      Transport.ExAWS.Mock
      |> expect(:request!, fn %ExAws.Operation.S3{} = _operation ->
        # simulate what is raised by `request!` in case of failed `get_object`
        raise ExAws.Error, "something bad happened! maybe SENSITIVE INFO MAY BE HERE"
      end)

      {resp, logs} =
        with_log(fn ->
          proxy_conn()
          |> get("/resource/an-existing-s3-identifier")
        end)

      assert logs =~ ~r/something bad happened! maybe SENSITIVE INFO MAY BE HERE/

      # content of error should not be forwarded, instead we want a sanitized message
      assert resp.resp_body == "Bad Gateway"
      assert resp.status == 502

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-s3-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-s3-identifier"}}

      verify!(Transport.ExAWS.Mock)
    end
  end

  describe "GBFS item support" do
    test "handles GET /resource/:slug/gbfs.json (success case)" do
      slug = "an-existing-gbfs-identifier"
      ttl_in_seconds = 30
      base_url = "https://example.com/gbfs.json"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GBFS{
          identifier: slug,
          base_url: base_url,
          ttl: ttl_in_seconds,
          response_headers: [{"x-key", "foobar"}]
        }
      })

      setup_remote_responses(%{
        base_url => {200, %{"feed" => base_url, "data" => "foobar"} |> Jason.encode!()}
      })

      resp = proxy_conn() |> get("/resource/#{slug}/gbfs.json")

      assert resp.resp_body ==
               %{"feed" => "http://proxy.127.0.0.1:5100/resource/#{slug}/gbfs.json", "data" => "foobar"}
               |> Jason.encode!()

      assert resp.status == 200

      assert [
               {"cache-control", "max-age=0, private, must-revalidate"},
               {"x-request-id", _},
               {"access-control-allow-origin", "*"},
               {"access-control-expose-headers", "*"},
               # present in `response_headers`, should have been added
               {"x-key", "foobar"}
             ] = resp.resp_headers

      # Cache exist and has been set up properly
      assert {:ok, ["resource:an-existing-gbfs-identifier:gbfs.json"]} == Cachex.keys(Unlock.Shared.cache_name())
      {:ok, ttl} = Cachex.ttl(Unlock.Shared.cache_name(), "resource:an-existing-gbfs-identifier:gbfs.json")
      assert_in_delta ttl / 1_000, ttl_in_seconds, 1

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-gbfs-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-gbfs-identifier"}}
    end

    test "handles GET /resource/:slug/system_information.json (success case)" do
      slug = "an-existing-gbfs-identifier"
      ttl_in_seconds = 30
      base_url = "https://example.com/gbfs.json"
      requested_url = "https://example.com/system_information.json"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GBFS{
          identifier: slug,
          base_url: base_url,
          ttl: ttl_in_seconds,
          response_headers: [{"x-key", "foobar"}]
        }
      })

      setup_remote_responses(%{
        requested_url => {200, %{"feed" => requested_url, "data" => "foobar"} |> Jason.encode!()}
      })

      resp = proxy_conn() |> get("/resource/#{slug}/system_information.json")

      assert resp.resp_body ==
               %{"feed" => "http://proxy.127.0.0.1:5100/resource/#{slug}/system_information.json", "data" => "foobar"}
               |> Jason.encode!()

      assert resp.status == 200

      assert [
               {"cache-control", "max-age=0, private, must-revalidate"},
               {"x-request-id", _},
               {"access-control-allow-origin", "*"},
               {"access-control-expose-headers", "*"},
               # present in `response_headers`, should have been added
               {"x-key", "foobar"}
             ] = resp.resp_headers

      # Cache exist and has been set up properly
      assert {:ok, ["resource:an-existing-gbfs-identifier:system_information.json"]} == Cachex.keys(Unlock.Shared.cache_name())
      {:ok, ttl} = Cachex.ttl(Unlock.Shared.cache_name(), "resource:an-existing-gbfs-identifier:system_information.json")
      assert_in_delta ttl / 1_000, ttl_in_seconds, 1

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-gbfs-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-gbfs-identifier"}}
    end

    test "config with query string, request and response headers" do
      slug = "an-existing-gbfs-identifier"
      ttl_in_seconds = 30
      base_url = "https://example.com/gbfs.json?key=foobar"
      requested_url = "https://example.com/system_information.json?key=foobar"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GBFS{
          identifier: slug,
          base_url: base_url,
          ttl: ttl_in_seconds,
          request_headers: [{"x-key", "foo"}],
          response_headers: [{"x-key", "foobar"}]
        }
      })

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn ^requested_url, [{"x-key", "foo"}], [] ->
        body = %{"feed" => requested_url, "data" => "foobar"} |> Jason.encode!()
        %Unlock.HTTP.Response{body: body, status: 200, headers: [{"ETag", "etag-value"}]}
      end)

      resp = proxy_conn() |> get("/resource/#{slug}/system_information.json")

      assert resp.resp_body ==
               %{
                 "feed" => "http://proxy.127.0.0.1:5100/resource/#{slug}/system_information.json",
                 "data" => "foobar"
               }
               |> Jason.encode!()

      assert resp.status == 200

      assert [
               {"cache-control", "max-age=0, private, must-revalidate"},
               {"x-request-id", _},
               {"access-control-allow-origin", "*"},
               {"access-control-expose-headers", "*"},
               # present in the response, should be forwarded
               {"etag", "etag-value"},
               # present in `response_headers`, should have been added
               {"x-key", "foobar"}
             ] = resp.resp_headers

      # Cache exist and has been set up properly
      assert {:ok, ["resource:an-existing-gbfs-identifier:system_information.json"]} == Cachex.keys(Unlock.Shared.cache_name())
      {:ok, ttl} = Cachex.ttl(Unlock.Shared.cache_name(), "resource:an-existing-gbfs-identifier:system_information.json")
      assert_in_delta ttl / 1_000, ttl_in_seconds, 1

      assert_received {:telemetry_event, [:proxy, :request, :internal], %{},
                       %{target: "proxy:an-existing-gbfs-identifier"}}

      assert_received {:telemetry_event, [:proxy, :request, :external], %{},
                       %{target: "proxy:an-existing-gbfs-identifier"}}
    end

    test "root request without endpoint" do
      slug = "an-existing-gbfs-identifier"
      ttl_in_seconds = 30
      base_url = "https://example.com/gbfs.json"

      setup_proxy_config(%{
        slug => %Unlock.Config.Item.GBFS{
          identifier: slug,
          base_url: base_url,
          ttl: ttl_in_seconds
        }
      })

      resp = proxy_conn() |> get("/resource/#{slug}")

      assert resp.status == 404

      assert {:ok, []} == Cachex.keys(Unlock.Shared.cache_name())
    end
  end

  defp setup_telemetry_handler do
    events = Unlock.Telemetry.proxy_request_event_names()

    # NOTE: this is deregistering the `apps/transport`
    # handlers, which will otherwise create Ecto records.
    # Also see https://github.com/etalab/transport-site/issues/3975
    # since there is over-coupling of `apps/transport` tests which
    # could bring your database to a broken state for tests if you
    # comment the detach temporarily while running the tests.
    # Situation to be improved, obviously.
    events
    |> Enum.flat_map(&:telemetry.list_handlers(&1))
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.each(&:telemetry.detach/1)

    test_pid = self()
    # inspired by https://github.com/dashbitco/broadway/blob/main/test/broadway_test.exs
    :telemetry.attach_many(
      "test-handler-#{System.unique_integer()}",
      events,
      fn name, measurements, metadata, _ ->
        # NOTE: if you change the tuple size, please review all
        # `refute_received` calls to make sure they remain useful.
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end
end
