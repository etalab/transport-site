defmodule GBFS.RedirectControllerTest do
  use GBFS.ConnCase, async: true

  describe "Montpellier" do
    test "it redirects", %{conn: conn} do
      klervi_base = "https://montpellier-fr-smoove.klervi.net/gbfs/"

      expected = %{
        "gbfs.json" => klervi_base <> "gbfs.json",
        "system_information.json" => klervi_base <> "en/system_information.json",
        "station_information.json" => klervi_base <> "en/station_information.json",
        "station_status.json" => klervi_base <> "en/station_status.json"
      }

      for {path, target} <- expected do
        conn = conn |> get("/gbfs/montpellier/#{path}")
        assert redirected_to(conn, 301) == target
      end
    end

    test "unknown path", %{conn: conn} do
      assert conn |> get("/gbfs/montpellier/foo") |> text_response(404) == "404 not found"
    end
  end
end
