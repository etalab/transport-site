defmodule NeTExTestData do
  import ExUnit.Assertions, only: [assert: 1]

  @moduledoc """
  Shared test data for NeTEx validation controller tests.

  Used by both `ResourceControllerTest` and `ValidationControllerTest` to avoid
  duplicating result maps and multi-validation builder logic across the two files.
  """

  # All supported NeTEx validator versions, tested across multiple test suites.
  def all_versions do
    ["0.1.0", "0.2.0", "0.2.1", "0.2.2"]
  end

  def versions(pattern) do
    all_versions() |> Enum.filter(fn version -> Regex.match?(pattern, version) end)
  end

  # Errors in both XSD and base-rules categories with mixed severities.
  # Used by category stats tests — summary_from_binary should report the worst
  # severity per category.
  def category_stats_result("0.2." <> _) do
    %{
      "xsd-schema" => [
        %{"code" => "xsd-1", "criticity" => "error", "message" => "XSD error 1"},
        %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD warning"}
      ],
      "base-rules" => [
        %{"code" => "rule-1", "criticity" => "warning", "message" => "Base rule warning"}
      ]
    }
  end

  def category_stats_result("0.1.0") do
    %{
      "xsd-1" => [
        %{"code" => "xsd-1", "criticity" => "error", "message" => "XSD error 1"}
      ],
      "xsd-2" => [
        %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD warning"}
      ],
      "rule-1" => [
        %{"code" => "rule-1", "criticity" => "warning", "message" => "Base rule warning"}
      ]
    }
  end

  def warnings_only("0.2." <> _) do
    %{
      "xsd-schema" => [
        %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD warning"}
      ],
      "base-rules" => [
        %{"code" => "rule-1", "criticity" => "warning", "message" => "Base rule warning"}
      ]
    }
  end

  def warnings_only("0.1.0") do
    %{
      "xsd-2" => [
        %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD warning"}
      ],
      "rule-1" => [
        %{"code" => "rule-1", "criticity" => "warning", "message" => "Base rule warning"}
      ]
    }
  end

  # Errors in both categories — used by filtering tests.
  def filtered_result do
    %{
      "xsd-schema" => [
        %{"code" => "xsd-1", "criticity" => "error", "message" => "XSD-only error"},
        %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD-only warning"}
      ],
      "base-rules" => [
        %{"code" => "rule-1", "criticity" => "error", "message" => "Base-rule only error"}
      ]
    }
  end

  # Pagination test issues — `count` distinct items (default 45, spanning 3 pages).
  def pagination_issues(count \\ 45) do
    for i <- 1..count do
      %{"code" => "rule-#{i}", "criticity" => "warning", "message" => "Page-test issue #{i}"}
    end
  end

  # Builds the common fields for a `multi_validation` insert from a result map.
  # Returns a keyword list suitable for passing directly to `insert(:multi_validation, ...)`
  # or `Ecto.Changeset.change(..., ...)`.
  def build_multi_validation_opts(version, result) do
    errors = result |> Map.values() |> List.flatten()
    adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
    df = adapter.to_dataframe(errors)

    [
      validator: Transport.Validators.NeTEx.Validator.validator_name(),
      validator_version: version,
      digest: adapter.digest(df),
      binary_result: adapter.to_binary_result(errors),
      max_error: "error",
      metadata: %DB.ResourceMetadata{metadata: %{}, modes: [], features: []},
      validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
    ]
  end

  # Asserts that the rendered NeTEx category stats page shows correct severity
  # counts and tab styling (icons + CSS variants) for XSD and base-rules categories.
  # Expects `body` to be a Floki document.
  def assert_netex_category_stats(body) do
    text_body = Floki.text(body)

    # XSD tab shows worst severity (error) and total count (1 error + 1 warning = 2),
    # base-rules shows warning with its single item
    assert text_body =~ ~r{XSD\s+– 2 erreurs}
    # NOTE: "Règles de base" warnings are currently displayed as errors in the UI.
    # This assertion verifies they will display correctly once that bug is fixed.
    assert text_body =~ ~r{Règles de base\s+– 1 avertissement}

    # Check category tabs have correct icons and colors
    tabs = Floki.find(body, ".colorful")

    xsd_tab = Enum.find(tabs, fn tab -> Floki.text(tab) =~ "XSD" end)
    assert Floki.attribute(xsd_tab, "class") |> Enum.any?(&String.contains?(&1, "variant-error"))
    assert Floki.find(xsd_tab, "i.fa-xmark.text-error") |> length() == 1
    assert Floki.find(xsd_tab, "i.fa-triangle-exclamation.text-warning") |> length() == 0

    # NOTE: same as above — the tab currently shows variant-error because warnings
    # are misclassified as errors. This assertion will need updating once fixed.
    rules_tab = Enum.find(tabs, fn tab -> Floki.text(tab) =~ "Règles de base" end)
    assert Floki.attribute(rules_tab, "class") |> Enum.any?(&String.contains?(&1, "variant-warning"))
    assert Floki.find(rules_tab, "i.fa-xmark.text-error") |> length() == 0
    assert Floki.find(rules_tab, "i.fa-triangle-exclamation.text-warning") |> length() == 1
  end

  # Same as above but for pagination tests where max_error is "warning".
  # `result` must be a flat list of error maps (not a category-keyed map).
  def build_multi_validation_opts_pagination(version, result) do
    adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
    df = adapter.to_dataframe(result)

    [
      validator: Transport.Validators.NeTEx.Validator.validator_name(),
      validator_version: version,
      digest: adapter.digest(df),
      binary_result: adapter.to_binary_result(result),
      max_error: "warning",
      metadata: %DB.ResourceMetadata{metadata: %{}, modes: [], features: []},
      validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
    ]
  end

  # ============================================================================
  # Component test helpers — single builder with keyword overrides
  # ============================================================================

  @doc """
  Builds a %NeTExValidationDetails{} struct for component rendering tests.

  All fields use sensible defaults — pass keyword overrides to change specific values.
  """
  def netex_validation_details(opts \\ []) do
    defaults = %TransportWeb.NeTExValidationDetails{
      metadata: %{"xsd_version" => "1.0"},
      adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0,
      download_url: "/report/42",
      has_errors?: false,
      max_severity: %{"max_level" => "NoError", "worst_occurrences" => 0},
      retention_days: 30
    }

    Map.new(Keyword.merge(Map.to_list(defaults), opts))
  end

  # --- Variant builders (each delegates to netex_validation_details/1) ---

  @doc "v0.1.0 clean report (the CaseClauseError regression case)"
  def netex_validation_details_v0_1_0_clean do
    netex_validation_details(
      adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0,
      download_url: nil,
      has_errors?: false,
      max_severity: %{"max_level" => "NoError", "worst_occurrences" => 0},
      summary: [],
      stats: %{},
      issues_page: %Scrivener.Page{entries: []}
    )
  end

  @doc "v0.2.x clean report with category tabs still visible"
  def netex_validation_details_v0_2_x_clean do
    netex_validation_details(
      download_url: nil,
      has_errors?: false,
      max_severity: %{"max_level" => "NoError", "worst_occurrences" => 0},
      summary: [
        %{"category" => "xsd-schema", "stats" => %{"criticity" => "NoError", "count" => 0}},
        %{"category" => "base-rules", "stats" => %{"criticity" => "NoError", "count" => 0}},
        %{"category" => "french-profile", "stats" => %{"criticity" => "NoError", "count" => 0}}
      ],
      xsd_errors: [],
      issues_page: %Scrivener.Page{entries: []}
    )
  end

  @doc "Report with error+warning severity errors across XSD and base-rules categories"
  def netex_validation_details_with_errors(filter \\ %{}) do
    netex_validation_details(
      has_errors?: true,
      max_severity: %{"max_level" => "error", "worst_occurrences" => 3},
      filter: filter,
      summary: [
        %{"category" => "xsd-schema", "stats" => %{"criticity" => "error", "count" => 2}},
        %{"category" => "base-rules", "stats" => %{"criticity" => "warning", "count" => 1}}
      ],
      xsd_errors: [
        %{"counts" => 2, "message" => "XSD error message"},
        %{"counts" => 1, "message" => "Another XSD error"}
      ],
      issues_page:
        paginated_issues([
          %{"criticity" => "error", "message" => "Test error", "resource" => %{"filename" => "test.xml", "line" => 42}}
        ])
    )
  end

  @doc "Report with warning-only severity errors"
  def netex_validation_details_with_warnings do
    netex_validation_details(
      has_errors?: true,
      max_severity: %{"max_level" => "warning", "worst_occurrences" => 2},
      summary: [
        %{"category" => "xsd-schema", "stats" => %{"criticity" => "warning", "count" => 1}},
        %{"category" => "base-rules", "stats" => %{"criticity" => "warning", "count" => 1}}
      ],
      xsd_errors: [%{"counts" => 1, "message" => "XSD warning message"}],
      issues_page:
        paginated_issues([
          %{
            "criticity" => "warning",
            "message" => "Test warning",
            "resource" => %{"filename" => "warn.xml", "line" => 10}
          }
        ])
    )
  end

  @doc "Report with information-only severity errors"
  def netex_validation_details_with_information do
    netex_validation_details(
      has_errors?: true,
      max_severity: %{"max_level" => "information", "worst_occurrences" => 1},
      summary: [
        %{"category" => "xsd-schema", "stats" => %{"criticity" => "information", "count" => 1}}
      ],
      xsd_errors: [%{"counts" => 1, "message" => "XSD info message"}],
      issues_page:
        paginated_issues([
          %{
            "criticity" => "information",
            "message" => "Test information",
            "resource" => %{"filename" => "info.xml", "line" => 5}
          }
        ])
    )
  end

  @doc "Report with unknown-location issues (nil resource, nil filename)"
  def netex_validation_details_unknown_location(filter \\ %{}) do
    netex_validation_details(
      has_errors?: true,
      max_severity: %{"max_level" => "error", "worst_occurrences" => 3},
      filter: filter,
      summary: [%{"category" => "base-rules", "stats" => %{"criticity" => "error", "count" => 3}}],
      xsd_errors: [],
      issues_page:
        paginated_issues([
          %{"criticity" => "error", "message" => "Error with nil resource", "resource" => nil},
          %{
            "criticity" => "error",
            "message" => "Error with nil filename",
            "resource" => %{"filename" => nil, "line" => 10}
          },
          %{
            "criticity" => "error",
            "message" => "Error with valid location",
            "resource" => %{"filename" => "valid.xml", "line" => 20}
          }
        ])
    )
  end

  @doc "Report for testing French profile compliance (requires French Profile adapter)"
  def netex_validation_details_french_profile(compliance \\ :partial) do
    netex_validation_details(
      has_errors?: true,
      adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_2_1,
      max_severity: %{"max_level" => "error", "worst_occurrences" => 1},
      summary: [%{"category" => "french-profile", "stats" => %{"criticity" => "error", "count" => 1}}],
      xsd_errors: [],
      issues_page:
        paginated_issues([
          %{
            "criticity" => "error",
            "message" => "French profile error",
            "resource" => %{"filename" => "fp.xml", "line" => 1}
          }
        ])
    )
    |> Map.put(:french_profile_compliance, compliance)
  end

  # ============================================================================
  # Shared helpers
  # ============================================================================

  @doc """
  Wraps a list of issue maps in a properly initialised Scrivener.Page struct.
  """
  def paginated_issues(entries) do
    %Scrivener.Page{
      entries: entries,
      page_number: 1,
      page_size: 20,
      total_entries: length(entries),
      total_pages: 1
    }
  end
end
