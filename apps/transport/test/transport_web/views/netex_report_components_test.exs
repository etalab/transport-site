defmodule TransportWeb.NeTExReportComponentsTest do
  use ExUnit.Case, async: true
  alias TransportWeb.NeTExReportComponents
  require Phoenix.LiveViewTest

  defmodule MockResultsAdapter do
    # Helper: minimal adapter module that satisfies the component's interface.
    # The HEEx template calls @results_adapter.format_severity(...) via apply/3,
    # so only the module name (atom) is needed — no struct required.

    def format_severity(_max_level, count), do: "#{count}"
  end

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
            %{"message" => "Error 1", "resource" => %{"filename" => "file.xml", "line" => 42}},
            %{"message" => "Error 2", "resource" => %{"filename" => "data.xml", "line" => 100}}
          ]
        })

      assert html =~ "<table class=\"table netex_generic_issue\">"
      assert html =~ ">Error 1<"
      assert html =~ "file.xml"
      assert html =~ ">42<"
    end

    test "renders 'Unknown location' when resource is nil" do
      html =
        render(&NeTExReportComponents.netex_generic_issues/1, %{
          issues: [%{"message" => "Error", "resource" => nil}]
        })

      assert html =~ "Unknown location"
    end

    test "renders 'Unknown location' when filename or line is nil" do
      html =
        render(&NeTExReportComponents.netex_generic_issues/1, %{
          issues: [
            %{"message" => "a", "resource" => %{"filename" => nil, "line" => 10}},
            %{"message" => "b", "resource" => %{"filename" => "f.xml", "line" => nil}}
          ]
        })

      assert html =~ "Unknown location"
    end

    test "renders empty table when no issues" do
      html = render(&NeTExReportComponents.netex_generic_issues/1, %{issues: []})
      assert html =~ "<table class=\"table netex_generic_issue\">"
      refute html =~ "<tr class=\"message\">"
    end
  end

  describe "netex_validation_report_title/1" do
    test "default clause: renders heading and download button without adapter" do
      html =
        render(&NeTExReportComponents.netex_validation_report_title/1, %{
          validation_report_url: "https://example.com/report.csv"
        })

      assert html =~ "<h2>"
      assert html =~ "review report"
      assert html =~ "popovertarget=\"download-popup\""
    end

    test "adapter clause: renders formatted severity" do
      html =
        render(&NeTExReportComponents.netex_validation_report_title/1, %{
          validation_report_url: "https://example.com/report.csv",
          results_adapter: MockResultsAdapter,
          max_severity: %{"max_level" => "error", "worst_occurrences" => 5}
        })

      assert html =~ "<h2>"
      assert html =~ "5"
    end

    test "adapter clause with level 4 renders h4" do
      html =
        render(&NeTExReportComponents.netex_validation_report_title/1, %{
          validation_report_url: "https://example.com/report.csv",
          results_adapter: MockResultsAdapter,
          max_severity: %{"max_level" => "warning", "worst_occurrences" => 3},
          level: 4
        })

      assert html =~ "<h4>"
    end
  end
end
