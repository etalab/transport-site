defmodule GBFS.IndexControllerTest do
  use TransportWeb.ConnCase, async: true

  describe "GET /" do
    test "returns properly formatted hrefs", %{conn: conn} do
      first_href = conn
        |> get("/gbfs")
        |> json_response(200)
        |> Enum.at(0)
        |> get_in(["gbfs", "_links", "gbfs.json", "href"])
        |> URI.parse
        |> Map.get(:path)

      # NOTE: this order is deterministic & established via the code
      # see bottom of GBFS.Router for the static definition.
      assert first_href == "/gbfs/vcub/gbfs.json"
    end
  end
end
