defmodule TransportWeb.Live.GTFSDiffSelectLiveTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  doctest TransportWeb.Live.GTFSDiffSelectLive, import: true
  doctest TransportWeb.Live.GTFSDiffSelectLive.Results, import: true
  doctest TransportWeb.Live.GTFSDiffSelectLive.Setup, import: true

  alias TransportWeb.Live.GTFSDiffSelectLive.Results

  describe "results" do
    test "display results for similar GTFS files" do
      gtfs_original_file_name_1 = "base.zip"
      gtfs_original_file_name_2 = "modified.zip"

      results = %{
        context: %{
          "gtfs_original_file_name_1" => gtfs_original_file_name_1,
          "gtfs_original_file_name_2" => gtfs_original_file_name_2
        },
        diff_file_url: "http://localhost:5000/gtfs-diff.csv",
        diff_summary: %{}
      }

      html = render_results(error_msg: nil, profile: "core", results: results)

      assert html |> Floki.find("p:nth-child(3)") |> Floki.text() ==
               "Les fichier GTFS #{gtfs_original_file_name_2} et #{gtfs_original_file_name_1} sont similaires."

      assert html |> Floki.find("div.dashboard") == []
    end

    test "display results for different GTFS files" do
      gtfs_original_file_name_1 = "base.zip"
      gtfs_original_file_name_2 = "modified.zip"

      results = %{
        context: %{
          "gtfs_original_file_name_1" => gtfs_original_file_name_1,
          "gtfs_original_file_name_2" => gtfs_original_file_name_2
        },
        diff_file_url: "http://localhost:5000/gtfs-diff.csv",
        diff_summary: %{
          "add" => [{{"stop_times.txt", "add", "row"}, 1}],
          "delete" => [
            {{"agency.txt", "delete", "file"}, 1},
            {{"calendar.txt", "delete", "column"}, 1}
          ]
        }
      }

      html = render_results(error_msg: nil, profile: "core", results: results)

      assert html |> Floki.find("p:nth-child(3)") |> Floki.text() ==
               "Le fichier GTFS #{gtfs_original_file_name_2} comporte les différences ci-dessous par rapport au fichier GTFS #{gtfs_original_file_name_1} :"

      navigation = html |> Floki.find("div.dashboard aside")

      assert navigation |> Floki.find("a") |> texts == [
               "agency.txt",
               "calendar.txt",
               "stop_times.txt"
             ]

      assert navigation |> Floki.find("a.active") |> Floki.text() == "agency.txt"

      selected_file_details = html |> Floki.find("div.dashboard div.main")
      assert selected_file_details |> Floki.find("h4") |> texts == ["Résumé"]
      assert selected_file_details |> Floki.find("ul li") |> texts == ["supprimé 1 fichier"]
    end
  end

  defp texts(html_tuples) do
    Enum.map(html_tuples, fn tuple ->
      tuple |> Floki.text() |> clean_whitespaces()
    end)
  end

  defp clean_whitespaces(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp render_results(args) do
    render_component(&Results.results_step/1, args)
    |> Floki.parse_document!()
    |> Floki.find("div#gtfs-diff-results")
  end
end
