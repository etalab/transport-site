defmodule GBFS.IndexControllerTest do
  use GBFS.ConnCase, async: true

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
      assert first_href == "http://localhost/gbfs/vcub/gbfs.json"
    end
  end

  test "404 pages", %{conn: conn} do
    expected_regex = ~r"^Network not found. See available data:"
    assert conn |> get("/gbfs/foo") |> text_response(404) =~ expected_regex
    assert conn |> get("/gbfs/foo/gbfs.json") |> text_response(404) =~ expected_regex
  end
end
