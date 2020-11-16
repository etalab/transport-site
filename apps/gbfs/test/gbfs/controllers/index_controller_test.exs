defmodule GBFS.IndexControllerTest do
  use TransportWeb.ConnCase, async: true

  describe "GET /" do
    test "returns correct absolute urls", %{conn: conn} do
      first_href =
        conn
        |> get("/gbfs")
        |> json_response(200)
        |> Enum.at(0)
        |> get_in(["gbfs", "_links", "gbfs.json", "href"])

      port = :transport
        |> Application.get_env(TransportWeb.Endpoint)
        |> get_in([:http, :port])

      # NOTE: the order of "networks" is deterministic & established via the code,
      # which means we can fix data for the test
      # see bottom of GBFS.Router for the static definition.
      # we're looking both to ensure we have a full url here, and that the path is as expected
      assert first_href == "http://127.0.0.1:#{port}/gbfs/vcub/gbfs.json"
    end
  end
end
