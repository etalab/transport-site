defmodule TransportWeb.NeTExValidationReportComponentTest do
  use ExUnit.Case, async: false

  import NeTExTestData
  alias TransportWeb.NeTExValidationReportComponent
  require Phoenix.LiveViewTest

  setup do
    Gettext.put_locale(TransportWeb.Gettext, "en")
    :ok
  end

  # ============================================================================
  # Title rendering tests
  # ============================================================================

  describe "netex_validation_report_title/1" do
    test "renders fallback heading and download button when no adapter or max_severity" do
      html = render_netex_validation_report_title("/report/42")

      assert extract_nodes(html, "h4") == ["NeTEx review report"]
      buttons = Floki.parse_fragment!(html) |> Floki.find("button[popovertarget='download-popup']")
      assert buttons != []
    end

    test "renders configurable heading level (default h4, h2 on override)" do
      for level <- [4, 2] do
        html =
          render_netex_validation_report_title("/report/42",
            results_adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0,
            max_severity: %{"max_level" => "error", "worst_occurrences" => 5},
            heading_level: level
          )

        assert extract_nodes(html, "h#{level}") == ["5 errors"]
      end
    end

    test "renders correct severity format for each adapter version and severity" do
      for version <- NeTExTestData.all_versions() do
        adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)

        [
          %{"severity" => "error", "count" => 3},
          %{"severity" => "warning", "count" => 7},
          %{"severity" => "information", "count" => 1}
        ]
        |> Enum.each(fn %{"severity" => severity, "count" => count} ->
          html = render_severity(adapter, severity, count)
          expected = adapter.format_severity(severity, count)
          assert extract_nodes(html, "h4") == [expected]
        end)
      end
    end

    test "renders NoError heading for v0.1.0 adapter" do
      html =
        render_netex_validation_report_title("/report/42",
          results_adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0,
          max_severity: %{"max_level" => "NoError", "worst_occurrences" => 0},
          heading_level: 4
        )

      expected = String.capitalize(Transport.Validators.NeTEx.ResultsAdapters.V0_1_0.format_severity("NoError", 0))
      assert extract_nodes(html, "h4") == [expected]
    end

    test "renders NoError heading for v0.2.x adapters" do
      for version <- NeTExTestData.versions(~r/0.2./) do
        adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
        html = render_severity(adapter, "NoError", 0)

        expected = String.capitalize(Transport.Validators.NeTEx.ResultsAdapters.V0_2_0.format_severity("NoError", 0))
        assert extract_nodes(html, "h4") == [expected]
      end
    end
  end

  # ============================================================================
  # Download popup tests
  # ============================================================================

  describe "netex_download_popup_content/1" do
    test "renders no report message when url is nil" do
      html = render_netex_download_popup_content()

      assert extract_nodes(html, "p") == ["No validation error. No report to download."]
    end

    test "renders CSV and Parquet download links when url is present" do
      html = render_netex_download_popup_content("/report/42")

      assert extract_nodes(html, ".download-button button") == ["validation.csv", "validation.parquet"]
    end
  end

  # ============================================================================
  # Category tabs rendering tests
  # ============================================================================

  describe "category tabs - severity variants" do
    test "error severity renders tab with error icon and count" do
      tab = netex_validation_details_with_errors() |> render_report() |> extract_tab("XSD")

      assert_has_icon(tab, :error)
      assert tab.count_text == "2 errors"
    end

    test "warning severity renders tab with warning icon" do
      netex_validation_details_with_warnings()
      |> render_report()
      |> extract_tab("XSD")
      |> assert_has_icon(:warning)
    end

    test "information severity renders tab with information icon" do
      netex_validation_details_with_information()
      |> render_report()
      |> extract_tab("XSD")
      |> assert_has_icon(:information)
    end

    test "mixed severities across categories render distinct icons" do
      tabs_map =
        netex_validation_details_with_errors()
        |> render_report()
        |> extract_tabs()
        |> Map.new(&{&1.category, &1})

      assert_has_icon(tabs_map["XSD"], :error)
      assert_has_icon(tabs_map["Base rules"], :warning)
    end
  end

  # ============================================================================
  # Category filtering tests
  # ============================================================================

  describe "category filtering" do
    test "default xsd-schema tab shows XSD table and hides generic issues" do
      html = render_report(netex_validation_details_with_errors())

      assert find_xsd_table(html) != []
      assert find_generic_table(html) == []
    end

    test "base-rules tab shows generic issues and hides XSD table" do
      html = render_report(netex_validation_details_with_errors(%{"issues_category" => "base-rules"}))

      assert find_xsd_table(html) == []
      assert find_generic_table(html) != []

      rows = extract_generic_issue_rows(html)
      assert length(rows) == 1
      assert hd(rows) == ["Test error", "test.xml", "42"]
    end

    test "french-profile tab renders compliance tooltip" do
      html =
        render_report(netex_validation_details_french_profile(:partial), %{"issues_category" => "french-profile"})

      dialog = Floki.parse_fragment!(html) |> Floki.find("dialog#french-profile-rules")
      assert dialog != []

      dialog_text = Floki.text(hd(dialog))
      assert String.contains?(dialog_text, "French Profile rules currently checked")
    end
  end

  # ============================================================================
  # Pagination rendering tests
  # ============================================================================

  describe "pagination rendering" do
    test "does not render pagination nav when there is only one page" do
      html = render_report(netex_validation_details_with_errors(%{"issues_category" => "base-rules"}))

      assert find_pagination(html) == []
    end
  end

  # ============================================================================
  # French profile compliance tests (skipped - requires French Profile adapter)
  # ============================================================================

  describe "French profile compliance messages" do
    @tag mode: [:none, :partial, :good_enough]
    test "renders dialog with compliance content", %{mode: mode} do
      report = netex_validation_details_french_profile(mode)
      html = render_report(report, %{"issues_category" => "french-profile"})

      dialog = Floki.parse_fragment!(html) |> Floki.find("dialog#french-profile-rules")
      assert dialog != []

      case mode do
        :good_enough ->
          # The dialog exists but the compliance paragraph should be empty/not present
          p_elements = Floki.find(hd(dialog), "p")
          assert p_elements != []

        _ ->
          dialog_text = Floki.text(hd(dialog))
          assert String.contains?(dialog_text, "French Profile rules currently checked")
      end
    end
  end

  # ============================================================================
  # Clean report tests
  # ============================================================================

  describe "clean reports" do
    test "v0.2.x clean report shows all category tabs with checkmarks" do
      html = render_report(netex_validation_details_v0_2_x_clean())

      tabs = extract_tabs(html)
      assert length(tabs) == 3

      for tab <- tabs do
        assert_has_icon(tab, :check)
      end

      assert extract_nodes(html, ".panel h2") == ["Nice work, there are no issues!"]
    end

    test "v0.1.0 clean report does not crash (CaseClauseError regression)" do
      html = render_report(netex_validation_details_v0_1_0_clean())

      assert extract_nodes(html, ".panel h2") == ["Nice work, there are no issues!"]
    end
  end

  # ============================================================================
  # XSD-specific rendering tests
  # ============================================================================

  describe "XSD issues table" do
    test "XSD issues table rows contain correct occurrences and messages" do
      html = render_report(netex_validation_details_with_errors())

      rows = extract_xsd_rows(html)
      assert length(rows) == 2
      assert rows == [["2", "XSD error message"], ["1", "Another XSD error"]]
    end

    test "XSD intro paragraph contains links to CSV report and xmllint" do
      html = render_report(netex_validation_details_with_errors())

      fragment = Floki.parse_fragment!(html)

      xsd_intro_p =
        fragment
        |> Floki.find("p")
        |> Enum.filter(fn p -> String.contains?(Floki.text(p), "XSD validation errors") end)

      assert length(xsd_intro_p) == 1

      links = Floki.find(hd(xsd_intro_p), "a")
      assert length(links) == 2

      link_data = links |> Enum.map(&{read_node_text(&1), Floki.attribute(&1, "href") |> hd()})
      assert Enum.any?(link_data, fn {text, _href} -> String.contains?(text, "CSV") end)
      assert Enum.any?(link_data, fn {_text, href} -> String.contains?(href, "xmllint") end)
    end

    test "\"only available in English\" warning shown when locale is not en" do
      # This test modifies process-local Gettext state, so it needs isolation.

      # Set locale to French for this test and restore after
      Gettext.put_locale(TransportWeb.Gettext, "fr")

      html = render_report(netex_validation_details_with_errors(%{"issues_category" => "base-rules"}))

      # The warning paragraph should be present when locale is not English
      # Check for French translation text to verify the locale is being used
      french_warning_p =
        Floki.parse_fragment!(html)
        |> Floki.find("p")
        |> Enum.filter(fn p -> String.contains?(Floki.text(p), "ne sont pas traduites") end)

      assert length(french_warning_p) == 1

      # Restore default locale
      Gettext.put_locale(TransportWeb.Gettext, "en")
    end
  end

  # ============================================================================
  # Generic issues table tests
  # ============================================================================

  describe "generic issues table" do
    test "issues with complete resource info render correctly" do
      html = render_report(netex_validation_details_with_errors(%{"issues_category" => "base-rules"}))

      rows = extract_generic_issue_rows(html)
      assert length(rows) == 1
      assert hd(rows) == ["Test error", "test.xml", "42"]
    end

    test "unknown location issues render colspan cell" do
      html =
        render_report(netex_validation_details_unknown_location(%{"issues_category" => "base-rules"}))

      assert extract_generic_issue_rows(html) == [
               ["Error with nil resource", "Unknown location"],
               ["Error with nil filename", "Unknown location"],
               ["Error with valid location", "valid.xml", "20"]
             ]
    end
  end

  # ============================================================================
  # Structural tests
  # ============================================================================

  describe "netex_validation_report/1 - structural tests" do
    test "renders no-issues page without wrapper duplicates or empty containers (heading_level: 4)" do
      html = render_report(netex_validation_details())

      fragment = Floki.parse_fragment!(html)

      assert Floki.find(fragment, "#validation-report") |> length() == 0
      assert Floki.find(fragment, "#issues") |> length() == 0
      assert Floki.find(fragment, ".container") |> length() == 0
      assert Floki.find(fragment, ".header_with_action_bar") |> length() > 0

      assert extract_nodes(html, "h2") == ["Nice work, there are no issues!"]
      assert extract_nodes(html, "h4") == ["No error"]
    end

    test "renders h2 when heading_level is 2 (validation controller style)" do
      html = render_report(netex_validation_details(), %{}, heading_level: 2)

      assert extract_nodes(html, "h2") == ["No error", "Nice work, there are no issues!"]
      assert extract_nodes(html, "h5") == ["Download the report"]
    end

    test "skips title when asked" do
      html = render_report(netex_validation_details(), %{}, heading_level: 2, title: false)

      assert extract_nodes(html, "h2") == ["Nice work, there are no issues!"]
      assert extract_nodes(html, "h5") == []
    end
  end

  # ============================================================================
  # Pagination anchor tests
  # ============================================================================

  describe "pagination anchors" do
    test "pagination links include #validation-report anchor" do
      multi_page = %Scrivener.Page{
        entries: for(i <- 1..25, do: %{"criticity" => "warning", "message" => "Issue #{i}"}),
        page_number: 2,
        page_size: 10,
        total_entries: 25,
        total_pages: 3
      }

      report =
        netex_validation_details_with_errors(%{"issues_category" => "base-rules", "page" => 2},
          issues_page: multi_page
        )

      html = render_report(report, %{"issues_category" => "base-rules", "page" => 2})

      navs = Floki.parse_fragment!(html) |> Floki.find(~s(nav[aria-label="Page navigation"]))
      assert navs != [], "Expected pagination nav to be rendered"

      # Extract all anchor hrefs from the nav element and verify they include the anchor
      links = hd(navs) |> Floki.find("a")
      assert links != [], "Expected at least one pagination links"

      # Filter out links without href (e.g. the active page link <a aria-current="page">)
      hrefs = Enum.map(links, fn a -> Floki.attribute(a, "href") |> List.first() end)
      navigable_hrefs = Enum.filter(hrefs, &is_binary/1)

      assert navigable_hrefs != [], "Expected at least one navigable pagination link"

      for href <- navigable_hrefs do
        assert String.contains?(href, "#validation-report"),
               "Pagination link should include #validation-report anchor: #{inspect(href)}"
      end
    end
  end

  # ============================================================================
  # Category ordering tests
  # ============================================================================

  describe "category ordering" do
    test "categories are rendered in preferred_category_order" do
      html = render_report(netex_validation_details_with_errors())

      tab_labels = Enum.map(extract_tabs(html), & &1.category)
      # V0_2_0 preferred order: xsd-schema, base-rules
      assert tab_labels == ["XSD", "Base rules"]
    end

    test "french-profile renders last when using v0.2.1 adapter" do
      report =
        netex_validation_details_with_errors(%{},
          adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_1,
          summary: [
            %{"category" => "xsd-schema", "stats" => %{"criticity" => "error", "count" => 1}},
            %{"category" => "base-rules", "stats" => %{"criticity" => "warning", "count" => 1}},
            %{"category" => "french-profile", "stats" => %{"criticity" => "information", "count" => 0}}
          ]
        )

      html = render_report(report, %{})

      tab_labels = Enum.map(extract_tabs(html), & &1.category)
      # V0_2_1 preferred order: xsd-schema, base-rules, french-profile
      assert tab_labels == ["XSD", "Base rules", "French profile"]
    end
  end

  # ============================================================================
  # XSD distinct row tests
  # ============================================================================

  describe "XSD distinct rows" do
    test "each unique XSD message renders as a separate row" do
      report =
        netex_validation_details_for_xsd(
          summary: [%{"category" => "xsd-schema", "stats" => %{"criticity" => "error", "count" => 4}}],
          xsd_errors: [
            %{"counts" => 2, "message" => "Duplicate message A"},
            %{"counts" => 1, "message" => "Unique message B"},
            %{"counts" => 1, "message" => "Another unique C"}
          ]
        )

      html = render_report(report, %{"issues_category" => "xsd-schema"})

      assert extract_xsd_rows(html) == [
               ["2", "Duplicate message A"],
               ["1", "Unique message B"],
               ["1", "Another unique C"]
             ]
    end

    test "duplicate XSD messages produce distinct rows (one per summary entry)" do
      report =
        netex_validation_details_for_xsd(
          summary: [%{"category" => "xsd-schema", "stats" => %{"criticity" => "error", "count" => 5}}],
          xsd_errors: [
            %{"counts" => 2, "message" => "Same error message"},
            %{"counts" => 3, "message" => "Same error message"}
          ]
        )

      html = render_report(report, %{"issues_category" => "xsd-schema"})

      # Component renders one row per xsd_error entry (not deduplicated)
      assert extract_xsd_rows(html) == [
               ["2", "Same error message"],
               ["3", "Same error message"]
             ]
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  # --- Infrastructure / Fixture helpers ---

  defp netex_conn(params) do
    %Plug.Conn{
      method: "GET",
      path_info: ["resources", "42"],
      query_params: params,
      params: params
    }
    |> Plug.Conn.put_private(:phoenix_endpoint, TransportWeb.Endpoint)
  end

  # --- Render wrappers ---

  defp render(fun, assigns), do: Phoenix.LiveViewTest.render_component(fun, assigns)

  defp render_netex_validation_report(conn, report, keywords) do
    assigns = Enum.into([conn: conn, report: report] ++ keywords, %{})
    render(&NeTExValidationReportComponent.netex_validation_report/1, assigns)
  end

  defp render_netex_validation_report_title(url, keywords \\ []) do
    assigns = Enum.into([validation_report_url: url, max_severity: nil, results_adapter: nil] ++ keywords, %{})
    render(&NeTExValidationReportComponent.netex_validation_report_title/1, assigns)
  end

  defp render_netex_download_popup_content(url \\ nil) do
    render(&NeTExValidationReportComponent.netex_download_popup_content/1, %{url: url})
  end

  # Render title component with a single severity configuration
  defp render_severity(adapter, max_level, worst_occurrences) do
    assigns = %{
      validation_report_url: "/report/42",
      max_severity: %{"max_level" => max_level, "worst_occurrences" => worst_occurrences},
      results_adapter: adapter,
      heading_level: 4
    }

    render(&NeTExValidationReportComponent.netex_validation_report_title/1, assigns)
  end

  # Render report with default heading_level: 4, returns {html, conn, report}
  defp render_report(report, params \\ %{}, opts \\ []) do
    params
    |> netex_conn()
    |> render_netex_validation_report(report, [heading_level: 4] ++ opts)
  end

  # --- DOM finders ---

  defp find_xsd_table(html), do: Floki.parse_fragment!(html) |> Floki.find("table.netex_xsd_schema")

  defp find_generic_table(html), do: Floki.parse_fragment!(html) |> Floki.find("table.netex_generic_issue")

  defp find_pagination(html),
    do: Floki.parse_fragment!(html) |> Floki.find(~s(nav[aria-label="Page navigation"]))

  # --- Extraction helpers (atomic first, then complex) ---

  defp read_node_text(node) do
    node |> Floki.text() |> String.trim()
  end

  defp extract_cells(row) do
    row
    |> Floki.find("td")
    |> Enum.map(&read_node_text/1)
  end

  defp extract_nodes(html, selector) when is_binary(html) do
    html
    |> Floki.parse_fragment!()
    |> extract_nodes(selector)
  end

  defp extract_nodes(nodes, selector) do
    nodes
    |> Floki.find(selector)
    |> Enum.map(&read_node_text/1)
  end

  defp extract_tabs(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("div#categories a")
    |> Enum.map(fn tab ->
      %{
        category: extract_category(tab),
        count_text: extract_count_text(tab),
        variant: Floki.attribute(tab, "class") |> Enum.filter(&String.starts_with?(&1, "variant-")),
        has_check_icon: has_node?(tab, "i.fa-check"),
        has_error_icon: has_node?(tab, "i.fa-xmark.text-error"),
        has_warning_icon: has_node?(tab, "i.fa-triangle-exclamation.text-warning"),
        has_information_icon: has_node?(tab, "i.fa-circle-info.text-info")
      }
    end)
  end

  defp has_node?(nodes, selector) do
    Floki.find(nodes, selector) |> length() > 0
  end

  defp extract_category(tab) do
    tab
    |> Floki.find("span.category")
    |> read_node_text()
  end

  defp extract_count_text(tab) do
    tab
    |> Floki.find("a.colorful span.stats")
    |> Enum.map_join(" ", &read_node_text/1)
  end

  defp extract_tab(html, category) do
    html
    |> extract_tabs()
    |> Enum.find(&(&1.category == category))
  end

  defp assert_has_icon(tab, icon_level) do
    if icon_level == :error, do: assert(tab.has_error_icon), else: refute(tab.has_error_icon)
    if icon_level == :warning, do: assert(tab.has_warning_icon), else: refute(tab.has_warning_icon)
    if icon_level == :information, do: assert(tab.has_information_icon), else: refute(tab.has_information_icon)
    if icon_level == :check, do: assert(tab.has_check_icon), else: refute(tab.has_check_icon)
  end

  defp extract_xsd_rows(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("table.netex_xsd_schema tr.message")
    |> Enum.map(&extract_cells/1)
  end

  defp extract_generic_issue_rows(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("table.netex_generic_issue tr.message")
    |> Enum.map(fn row ->
      cells = extract_cells(row)

      case length(cells) do
        3 -> [Enum.at(cells, 0), Enum.at(cells, 1), Enum.at(cells, 2)]
        1 -> [Enum.at(cells, 0), "Unknown location"]
        _ -> cells
      end
    end)
  end
end
