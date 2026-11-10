defmodule TransportWeb.NeTExValidationReportComponentTest do
  use ExUnit.Case, async: true

  import NeTExTestData
  alias TransportWeb.NeTExValidationReportComponent
  require Phoenix.LiveViewTest

  setup do
    Gettext.put_locale(TransportWeb.Gettext, "en")
    :ok
  end

  describe "netex_validation_report_title/1" do
    test "renders configurable heading level (default h4, h2 on override)" do
      for level <- [4, 2] do
        html =
          render_netex_validation_report_title("/report/42",
            results_adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0,
            max_severity: %{"max_level" => "error", "worst_occurrences" => 5},
            heading_level: level
          )

        assert extract_headings(html, "h#{level}") == ["5 errors"]
      end
    end

    test "renders fallback heading and download button when no adapter or max_severity" do
      html = render_netex_validation_report_title("/report/42")

      assert extract_headings(html, "h4") == ["NeTEx review report"]
      assert html =~ "popovertarget=\"download-popup\""
    end

    defp render_netex_validation_report_title(url, keywords \\ []) do
      assigns = Enum.into([validation_report_url: url, max_severity: nil, results_adapter: nil] ++ keywords, %{})
      render(&NeTExValidationReportComponent.netex_validation_report_title/1, assigns)
    end
  end

  describe "netex_download_popup_content/1" do
    test "renders no report message when url is nil" do
      # Need to make this function public for testing
      html = render_netex_download_popup_content()

      assert html =~ "No validation error. No report to download."
    end

    test "renders CSV and Parquet download links when url is present" do
      html = render_netex_download_popup_content("/report/42")

      assert html =~ "validation.csv"
      assert html =~ "validation.parquet"
    end

    defp render_netex_download_popup_content(url \\ nil) do
      render(&NeTExValidationReportComponent.netex_download_popup_content/1, %{url: url})
    end
  end

  describe "netex_validation_report/1 - structural tests" do
    test "renders no-issues page without wrapper duplicates or empty containers (heading_level: 4)" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render_netex_validation_report(conn, report, heading_level: 4)

      # Should NOT have an outer div with id="validation-report" - that's the caller's responsibility
      assert Floki.parse_fragment!(html) |> Floki.find("#validation-report") |> length() == 0
      # Should NOT have an outer div with id="issues" - that's the caller's responsibility
      assert Floki.parse_fragment!(html) |> Floki.find("#issues") |> length() == 0
      # Should NOT have an empty container div when there's no inner_block
      assert Floki.parse_fragment!(html) |> Floki.find(".container") |> length() == 0
      # Should have header_with_action_bar (title section)
      assert Floki.parse_fragment!(html) |> Floki.find(".header_with_action_bar") |> length() > 0
      # Should render h4 for the title
      assert extract_headings(html, "h4") == ["No error"]
      # Should show success message when no errors
      assert html =~ "Nice work, there are no issues!"
    end

    test "renders h2 when heading_level is 2 (validation controller style)" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render_netex_validation_report(conn, report, heading_level: 2)

      # Should have h2 for the title
      assert extract_headings(html, "h2") == ["No error", "Nice work, there are no issues!"]
      assert extract_headings(html, "h5") == ["Download the report"]
    end

    test "skips title when asked" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render_netex_validation_report(conn, report, heading_level: 2, title: false)

      # Only the summary title is presented, not the one with count and the
      # download popup
      assert extract_headings(html, "h2") == ["Nice work, there are no issues!"]
      assert extract_headings(html, "h5") == []
    end

    defp render_netex_validation_report(conn, report, keywords) do
      assigns = Enum.into([conn: conn, report: report] ++ keywords, %{})
      render(&NeTExValidationReportComponent.netex_validation_report/1, assigns)
    end
  end

  defp render(fun, assigns), do: Phoenix.LiveViewTest.render_component(fun, assigns)

  defp netex_conn(path_info \\ ["resources", "42"]) do
    %Plug.Conn{method: "GET", path_info: path_info, query_params: %{}, params: %{}}
  end

  defp extract_headings(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Enum.map(&read_heading_text/1)
  end

  defp read_heading_text(node) do
    node |> Floki.text() |> String.trim()
  end
end
