defmodule TransportWeb.NeTExReportComponentsTest do
  use ExUnit.Case, async: true
  alias TransportWeb.NeTExReportComponents
  require Phoenix.LiveViewTest

  # It doesn't really matter which adapter is used
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_0, as: ResultsAdapter

  defp render(fun, assigns), do: Phoenix.LiveViewTest.render_component(fun, assigns)

  setup do
    Gettext.put_locale(TransportWeb.Gettext, "en")
    :ok
  end

  describe "netex_generic_issues/1" do
    test "renders issues with complete resource info" do
      html =
        render(&NeTExReportComponents.netex_generic_issues/1, %{
          issues: [
            %{"criticity" => "error", "message" => "Error 1", "resource" => %{"filename" => "file.xml", "line" => 42}},
            %{"criticity" => "error", "message" => "Error 2", "resource" => %{"filename" => "data.xml", "line" => 100}},
            %{
              "criticity" => "warning",
              "message" => "Warning 1",
              "resource" => %{"filename" => "file.xml", "line" => 42}
            },
            %{
              "criticity" => "warning",
              "message" => "Warning 2",
              "resource" => %{"filename" => "data.xml", "line" => 100}
            },
            %{
              "criticity" => "information",
              "message" => "Information 1",
              "resource" => %{"filename" => "file.xml", "line" => 42}
            },
            %{
              "criticity" => "information",
              "message" => "Information 2",
              "resource" => %{"filename" => "data.xml", "line" => 100}
            }
          ],
          severity_counts: %{"error" => 2, "warning" => 2, "information" => 2},
          results_adapter: ResultsAdapter
        })

      assert extract_report_messages(html) == [
               ["Error", "Error 1", "file.xml", "42"],
               ["Error", "Error 2", "data.xml", "100"],
               ["Warning", "Warning 1", "file.xml", "42"],
               ["Warning", "Warning 2", "data.xml", "100"],
               ["Information", "Information 1", "file.xml", "42"],
               ["Information", "Information 2", "data.xml", "100"]
             ]

      # Severities stats should respect the severity level
      assert extract_severities(html) == [
               "2 errors",
               "2 warnings",
               "2 informations"
             ]
    end

    test "renders 'Unknown location' when resource or filename/line is nil" do
      # Single nil resource
      html =
        render(&NeTExReportComponents.netex_generic_issues/1, %{
          issues: [%{"criticity" => "error", "message" => "Error message", "resource" => nil}],
          severity_counts: %{"error" => 1},
          results_adapter: ResultsAdapter
        })

      assert extract_report_messages(html) == [
               ["Error", "Error message", "Unknown location"]
             ]

      assert extract_severities(html) == [
               "1 error"
             ]

      # Nil filename and nil line (two issues)
      html =
        render(&NeTExReportComponents.netex_generic_issues/1, %{
          issues: [
            %{"criticity" => "error", "message" => "a", "resource" => %{"filename" => nil, "line" => 10}},
            %{"criticity" => "error", "message" => "b", "resource" => %{"filename" => "f.xml", "line" => nil}}
          ],
          severity_counts: %{"error" => 2},
          results_adapter: ResultsAdapter
        })

      assert extract_report_messages(html) == [
               ["Error", "a", "Unknown location"],
               ["Error", "b", "Unknown location"]
             ]

      assert extract_severities(html) == [
               "2 errors"
             ]
    end

    test "renders empty table when no issues" do
      html =
        render(&NeTExReportComponents.netex_generic_issues/1, %{
          issues: [],
          severity_counts: %{},
          results_adapter: ResultsAdapter
        })

      assert extract_report_messages(html) == []
      assert extract_severities(html) == []
    end

    defp extract_report_messages(html) do
      html
      |> Floki.parse_fragment!()
      |> Floki.find("table.netex_generic_issue tr.message")
      |> Enum.map(&extract_cells/1)
    end

    defp extract_cells(row) do
      row
      |> Floki.find("td")
      |> Enum.map(fn td ->
        aria_label = Floki.attribute([td], "i", "aria-label") |> List.first()
        text = td |> Floki.text() |> String.trim()

        if aria_label do
          [aria_label, text]
        else
          [text]
        end
      end)
      |> List.flatten()
    end

    defp extract_severities(html) do
      html
      |> Floki.parse_fragment!()
      |> Floki.find("ul li")
      |> Enum.map(&Floki.text/1)
      |> Enum.map(&String.trim/1)
    end
  end

  describe "netex_validation_report_title/1" do
    test "default clause: renders heading and download button without adapter" do
      html =
        render(&NeTExReportComponents.netex_validation_report_title/1, %{
          validation_report_url: "https://example.com/report.csv"
        })

      assert extract_report_title(html, "h2") == "NeTEx review report"

      assert html =~ "popovertarget=\"download-popup\""
    end

    test "adapter clause: renders formatted severity" do
      html =
        render(&NeTExReportComponents.netex_validation_report_title/1, %{
          validation_report_url: "https://example.com/report.csv",
          results_adapter: ResultsAdapter,
          max_severity: %{"max_level" => "error", "worst_occurrences" => 5}
        })

      assert extract_report_title(html, "h2") == "5 errors"
    end

    test "adapter clause with level 4 renders h4" do
      html =
        render(&NeTExReportComponents.netex_validation_report_title/1, %{
          validation_report_url: "https://example.com/report.csv",
          results_adapter: ResultsAdapter,
          max_severity: %{"max_level" => "warning", "worst_occurrences" => 3},
          level: 4
        })

      assert extract_report_title(html, "h4") == "3 warnings"
    end

    defp extract_report_title(html, selector) do
      html
      |> Floki.parse_fragment!()
      |> Floki.find(selector)
      |> Floki.text()
      |> String.trim()
    end
  end
end
