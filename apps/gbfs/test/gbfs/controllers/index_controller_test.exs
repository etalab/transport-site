defmodule GBFS.IndexControllerTest do
  # This test is set to async because we need to enable the cache to test telemetry events
  use GBFS.ConnCase, async: false
  import AppConfigHelper

  setup do
    setup_telemetry_handler()
  end

  describe "GET /" do
    test "returns correct absolute urls", %{conn: conn} do
      first_href =
        conn
        |> get("/gbfs")
        |> json_response(200)
        |> Enum.at(0)
        |> get_in(["gbfs", "_links", "gbfs.json", "href"])

      # NOTE: the order of "networks" is deterministic & established via the code,
      # which means we can fix data for the test
      # see bottom of GBFS.Router for the static definition.
      # we're looking both to ensure we have a full url here, and that the path is as expected
      assert first_href == "http://localhost/gbfs/amiens/gbfs.json"
    end
  end

  test "404 pages", %{conn: conn} do
    # Enable PageCache + telemetry events
    enable_cache()

    expected_regex = ~r"^Network not found. See available data:"
    assert conn |> get("/gbfs/foo") |> text_response(404) =~ expected_regex
    assert conn |> get("/gbfs/foo/gbfs.json") |> text_response(404) =~ expected_regex

    # We did not receive telemetry events (ie metrics have not been saved to the database)
    refute_receive {:telemetry_event, [:gbfs, :request, _], %{}, %{}}
  end

  test "rate limiter is not enabled for the GBFS app", %{conn: conn} do
    [blocked_ip] = Application.fetch_env!(:phoenix_ddos, :blocklist_ips)

    conn
    |> Plug.Conn.put_req_header("x-forwarded-for", to_string(blocked_ip))
    |> get("/gbfs")
    |> json_response(200)
  end
end
