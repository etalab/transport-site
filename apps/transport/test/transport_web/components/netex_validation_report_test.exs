defmodule TransportWeb.NeTExValidationReportComponentTest do
  use ExUnit.Case, async: true

  import NeTExTestData
  alias TransportWeb.NeTExValidationReportComponent
  require Phoenix.LiveViewTest

  defp render(fun, assigns), do: Phoenix.LiveViewTest.render_component(fun, assigns)

  defp netex_conn(path_info \\ ["resources", "42"]) do
    %Plug.Conn{method: "GET", path_info: path_info, query_params: %{}, params: %{}}
  end

  setup do
    Gettext.put_locale(TransportWeb.Gettext, "en")
    :ok
  end

  describe "netex_validation_report_title/1" do
    test "renders h4 for error count (matching production HTML structure)" do
      html =
        render(&NeTExValidationReportComponent.netex_validation_report_title/1, %{
          validation_report_url: "/report/42",
          results_adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0,
          max_severity: %{"max_level" => "error", "worst_occurrences" => 5}
        })

      assert Floki.parse_fragment!(html) |> Floki.find("h4") |> length() == 1
      refute Floki.parse_fragment!(html) |> Floki.find("h2") |> length() > 0
    end

    test "renders fallback heading when no adapter or max_severity" do
      html =
        render(&NeTExValidationReportComponent.netex_validation_report_title/1, %{
          validation_report_url: "/report/42",
          max_severity: nil,
          results_adapter: nil
        })

      assert Floki.parse_fragment!(html) |> Floki.find("h2") |> length() == 1
      assert Floki.text(Floki.parse_fragment!(html) |> Floki.find("h2")) |> String.trim() == "NeTEx review report"
    end

    test "renders formatted severity when adapter and max_severity present" do
      html =
        render(&NeTExValidationReportComponent.netex_validation_report_title/1, %{
          validation_report_url: "/report/42",
          results_adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0,
          max_severity: %{"max_level" => "error", "worst_occurrences" => 5}
        })

      assert html =~ "5 errors"
    end

    test "renders download button with popover" do
      html =
        render(&NeTExValidationReportComponent.netex_validation_report_title/1, %{
          validation_report_url: "/report/42",
          max_severity: nil,
          results_adapter: nil
        })

      assert html =~ "popovertarget=\"download-popup\""
    end
  end

  describe "netex_download_popup_content/1" do
    test "renders no report message when url is nil" do
      # Need to make this function public for testing
      html = render(&NeTExValidationReportComponent.netex_download_popup_content/1, %{url: nil})

      assert html =~ "No validation error. No report to download."
    end

    test "renders CSV and Parquet download links when url is present" do
      html = render(&NeTExValidationReportComponent.netex_download_popup_content/1, %{url: "/report/42"})

      assert html =~ "validation.csv"
      assert html =~ "validation.parquet"
    end
  end

  describe "netex_validation_report/1 - structural tests" do
    test "does not add wrapper div with duplicate id='validation-report'" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render(&NeTExValidationReportComponent.netex_validation_report/1, %{report: report, conn: conn})

      # Should NOT have an outer div with id="validation-report" - that's the caller's responsibility
      assert Floki.parse_fragment!(html) |> Floki.find("#validation-report") |> length() == 0
    end

    test "does not add wrapper div with duplicate id='issues'" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render(&NeTExValidationReportComponent.netex_validation_report/1, %{report: report, conn: conn})

      # Should NOT have an outer div with id="issues" - that's the caller's responsibility
      assert Floki.parse_fragment!(html) |> Floki.find("#issues") |> length() == 0
    end

    test "does not render empty container div when no inner_block" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render(&NeTExValidationReportComponent.netex_validation_report/1, %{report: report, conn: conn})

      # Should NOT have an empty container div when there's no inner_block
      assert Floki.parse_fragment!(html) |> Floki.find(".container") |> length() == 0
    end

    test "renders title section with header_with_action_bar class" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render(&NeTExValidationReportComponent.netex_validation_report/1, %{report: report, conn: conn})

      # Should have header_with_action_bar (title section)
      assert Floki.parse_fragment!(html) |> Floki.find(".header_with_action_bar") |> length() > 0
    end

    test "renders no-issues message when has_errors? is false" do
      report = netex_validation_details()
      conn = netex_conn()

      html = render(&NeTExValidationReportComponent.netex_validation_report/1, %{report: report, conn: conn})

      assert html =~ "Nice work, there are no issues!"
    end
  end
end
