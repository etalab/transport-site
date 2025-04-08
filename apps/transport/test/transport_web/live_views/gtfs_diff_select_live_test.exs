defmodule TransportWeb.Live.GTFSDiffSelectLiveTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  doctest TransportWeb.Live.GTFSDiffSelectLive, import: true
  doctest TransportWeb.Live.GTFSDiffSelectLive.Differences, import: true
  doctest TransportWeb.Live.GTFSDiffSelectLive.Setup, import: true

  alias TransportWeb.GTFSDiffExplain
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
        diff_summary: %{},
        structural_changes: []
      }

      html = render_results(error_msg: nil, profile: "core", results: results)

      assert html |> Floki.find("p:nth-child(3)") |> Floki.text() ==
               "Les fichier GTFS #{gtfs_original_file_name_2} et #{gtfs_original_file_name_1} sont similaires."

      assert html |> Floki.find("div.dashboard") == []
    end

    test "display results for different GTFS files" do
      gtfs_original_file_name_1 = "base.zip"
      gtfs_original_file_name_2 = "modified.zip"

      diff = [
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "file"
        },
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"agency_id\"}"
        },
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"agency_name\"}"
        },
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"extra_column\"}"
        },
        %{
          "action" => "delete",
          "file" => "calendar.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"start_date\"}"
        },
        %{
          "action" => "delete",
          "file" => "calendar.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"end_date\"}"
        },
        %{
          "action" => "add",
          "file" => "calendar.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"monday\"}"
        },
        %{
          "action" => "add",
          "file" => "stop_times.txt",
          "target" => "row"
        },
        %{
          "action" => "update",
          "file" => "stops.txt",
          "identifier" => "{\"stop_id\":\"3000055\"}",
          "initial_value" => "{\"stop_name\":\"Hôpital\"}",
          "new_value" => "{\"stop_name\":\"Hôpital Arnauzand\"}",
          "target" => "row"
        },
        %{
          "action" => "update",
          "file" => "stops.txt",
          "identifier" => "{\"stop_id\":\"100\"}",
          "initial_value" => "{\"wheelchair_boarding\":\"0\"}",
          "new_value" => "{\"wheelchair_boarding\":\"1\"}",
          "target" => "row"
        },
        %{
          "action" => "delete",
          "file" => "feed_info.txt",
          "target" => "file"
        }
      ]

      diff_summary = diff |> GTFSDiffExplain.diff_summary()
      diff_explanations = diff |> GTFSDiffExplain.diff_explanations() |> drop_empty()
      structural_changes = diff |> GTFSDiffExplain.structural_changes()

      results = %{
        context: %{
          "gtfs_original_file_name_1" => gtfs_original_file_name_1,
          "gtfs_original_file_name_2" => gtfs_original_file_name_2
        },
        diff_file_url: "http://localhost:5000/gtfs-diff.csv",
        diff_summary: diff_summary,
        diff_explanations: diff_explanations,
        structural_changes: structural_changes
      }

      html = render_results(error_msg: nil, profile: "core", results: results)

      assert html |> Floki.find("div.panel > p:nth-child(3)") |> Floki.text() ==
               "Le fichier GTFS #{gtfs_original_file_name_2} comporte les différences ci-dessous par rapport au fichier GTFS #{gtfs_original_file_name_1} :"

      navigation = html |> Floki.find("div.dashboard aside")

      files = [
        "agency.txt",
        "calendar.txt",
        "feed_info.txt",
        "stop_times.txt",
        "stops.txt"
      ]

      assert navigation |> Floki.find("a") |> texts == files

      assert navigation |> Floki.find("a.active") |> Floki.text() == "agency.txt"

      selected_file_details = html |> Floki.find("div.dashboard div.main")
      assert selected_file_details |> Floki.find("h4") |> texts == ["agency.txt"]

      assert selected_file_details |> Floki.find("ul li") |> texts == [
               "agency_id",
               "agency_name",
               "extra_column colonne non standard"
             ]

      files
      |> Enum.each(fn selected_file ->
        results = Map.put(results, :selected_file, selected_file)

        render_results(error_msg: nil, profile: "core", results: results)
      end)
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

  defp drop_empty([]), do: nil
  defp drop_empty(otherwise), do: otherwise
end
