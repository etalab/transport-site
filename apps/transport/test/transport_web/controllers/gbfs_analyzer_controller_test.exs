defmodule TransportWeb.GbfsAnalyzerControllerTest do
  use TransportWeb.ConnCase, async: true

  import Mox
  setup :verify_on_exit!

  describe "GBFS analyzer" do
    test "the analyzer starting page", %{conn: conn} do
      conn = conn |> get(gbfs_analyzer_path(conn, :index))
      assert redirected_to(conn, 302) == live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive, type: "gbfs")
    end

    test "with a GBFS to analyze", %{conn: conn} do
      gbfs_url = "/gbfs.json"

      Transport.Shared.GBFSMetadata.Mock
      |> expect(:compute_feed_metadata, fn ^gbfs_url, cors_base_url ->
        assert cors_base_url == TransportWeb.Endpoint.url()

        %{
          system_details: %{name: "GBFS feed name"},
          feeds: ["station_information"]
        }
      end)

      conn = conn |> get(gbfs_analyzer_path(conn, :index, url: gbfs_url))
      assert html_response(conn, 200) =~ "Analyser un flux GBFS"
      assert html_response(conn, 200) =~ "GBFS feed name"
      assert html_response(conn, 200) =~ "station_information"
    end
  end
end
