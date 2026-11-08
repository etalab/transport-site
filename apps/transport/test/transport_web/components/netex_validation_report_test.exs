defmodule TransportWeb.NeTExValidationReportComponentTest do
  use ExUnit.Case, async: true

  alias TransportWeb.NeTExValidationReportComponent
  require Phoenix.LiveViewTest

  # It doesn't really matter which adapter is used
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_0, as: ResultsAdapter

  defp render(fun, assigns), do: Phoenix.LiveViewTest.render_component(fun, assigns)

  setup do
    Gettext.put_locale(TransportWeb.Gettext, "en")
    :ok
  end

  describe "netex_validation_report_title/1" do
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
          results_adapter: ResultsAdapter,
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
end
