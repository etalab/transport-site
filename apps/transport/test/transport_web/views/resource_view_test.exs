defmodule TransportWeb.ResourceViewTest do
  use ExUnit.Case, async: true
  doctest TransportWeb.ResourceView, import: true

  describe "markdown/1, used by _validation_report_mobilitydata_gtfs.html.heex" do
    test "a MobilityData rule keeps its HTML table" do
      rule = Transport.Validators.MobilityDataGTFSValidator.rule_for_code("mixed_case_recommended_field")
      {:safe, html} = TransportWeb.ResourceView.markdown(rule["description"])

      assert html =~ ~s(<table class="table">)
      assert html =~ "<td>"
      refute html =~ "&lt;table"
    end

    test "a MobilityData rule keeps its HTML links" do
      rule = Transport.Validators.MobilityDataGTFSValidator.rule_for_code("invalid_geometry")
      {:safe, html} = TransportWeb.ResourceView.markdown(rule["description"])

      assert html =~ ~r|<a href="https?://|
      refute html =~ "&lt;a href"
    end

    test "a MobilityData rule renders inline code" do
      rule = Transport.Validators.MobilityDataGTFSValidator.rule_for_code("equal_shape_distance_diff_coordinates")
      {:safe, html} = TransportWeb.ResourceView.markdown(rule["shortSummary"])

      assert html =~ "<code>shape_dist_traveled</code>"
    end

    test "dangerous attributes and tags are dropped from the rendered HTML" do
      {:safe, html} = TransportWeb.ResourceView.markdown("<img src=x onerror=alert(1)> <script>alert(1)</script>")

      assert html =~ ~s(<img src="x")
      refute html =~ "onerror"
      refute html =~ "<script"
    end
  end
end
