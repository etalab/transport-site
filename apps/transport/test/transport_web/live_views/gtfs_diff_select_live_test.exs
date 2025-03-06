defmodule TransportWeb.Live.GTFSDiffSelectLiveTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Phoenix.LiveViewTest
  import Mox
  alias Transport.Test.S3TestUtils

  doctest TransportWeb.Live.GTFSDiffSelectLive, import: true
  doctest TransportWeb.Live.GTFSDiffSelectLive.Results, import: true
  doctest TransportWeb.Live.GTFSDiffSelectLive.Setup, import: true

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "GET /tools/gtfs_diff" do
    test "loads properly", %{conn: conn} do
      get_view(conn) |> html_response(200)
    end

    test "supports uploads", %{conn: conn} do
      {:ok, view, _html} = live_view(conn)

      assert view |> has_element?("#gtfs-diff-input")
      refute view |> has_element?("#gtfs-diff-analysis")
      refute view |> has_element?("#gtfs-diff-results")

      assert view |> disabled_button("#uploaded-files button.small")
      assert view |> disabled_button(".actions button.button")
      assert view |> disabled_button(".actions button.primary")

      gtfs =
        file_input(view, "#upload-form", :gtfs, [
          %{
            last_modified: 1_594_171_879_000,
            name: "gtfs-reference.zip",
            content: File.read!("test/fixture/files/gtfs_diff/gtfs.zip"),
            size: 1_576,
            type: "application/zip"
          },
          %{
            last_modified: 1_594_171_879_000,
            name: "gtfs-modifications.zip",
            content: File.read!("test/fixture/files/gtfs_diff/gtfs_modified_files.zip"),
            size: 1_533,
            type: "application/zip"
          }
        ])

      assert render_upload(gtfs, "gtfs-reference.zip") =~ "100%"
      assert render_upload(gtfs, "gtfs-modifications.zip") =~ "100%"

      twice(fn ->
        S3TestUtils.s3_mock_stream_file(start_path: "live_view_upload", bucket: "transport-data-gouv-fr-gtfs-diff-test")
      end)

      refute view |> disabled_button("#uploaded-files button.small")
      refute view |> disabled_button(".actions button.button")
      refute view |> disabled_button(".actions button.primary")

      assert view |> element("#upload-form") |> render_submit() =~ "<h4>Traitement</h4>"

      assert_enqueued(
        worker: Transport.Jobs.GTFSDiff,
        args: %{"profile" => "core"}
      )

      refute view |> has_element?("#gtfs-diff-input")
      assert view |> has_element?("#gtfs-diff-analysis")
      refute view |> has_element?("#gtfs-diff-results")
    end
  end

  defp disabled_button(view, selector) do
    view |> element(selector) |> render() =~ "disabled"
  end

  defp get_view(conn) do
    path = live_path(conn, TransportWeb.Live.GTFSDiffSelectLive)

    conn |> get(path)
  end

  defp live_view(conn), do: get_view(conn) |> live()

  defp twice(func) do
    func.()
    func.()
  end
end
