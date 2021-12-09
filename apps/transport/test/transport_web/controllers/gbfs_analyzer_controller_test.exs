defmodule TransportWeb.GbfsAnalyzerControllerTest do
  use TransportWeb.ConnCase, async: true

  import Mox
  setup :verify_on_exit!

  describe "GBFS analyzer" do
    test "the analyzer starting page", %{conn: conn} do
      conn = conn |> get(gbfs_analyzer_path(conn, :index))
      assert html_response(conn, 200) =~ "Analyser un flux GBFS"
    end

    test "with an empty url", %{conn: conn} do
      conn = conn |> get(gbfs_analyzer_path(conn, :index, url: ""))
      assert html_response(conn, 200) =~ "Analyser un flux GBFS"
      refute html_response(conn, 200) =~ "Metadata"
    end

    test "with a GBFS to analyze", %{conn: conn} do
      gbfs_url = "/gbfs.json"

      Transport.GBFSMetadata.Mock
      |> expect(:compute_feed_metadata, fn ^gbfs_url ->
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
