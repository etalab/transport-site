defmodule NeTExTestData do
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
  def errors do
    [
      %{"code" => "xsd-1", "criticity" => "error", "message" => "XSD error 1"},
      %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD warning"},
      %{"code" => "rule-1", "criticity" => "warning", "message" => "Base rule warning"}
    ]
  end

  def warnings do
    [
      %{"code" => "xsd-2", "criticity" => "warning", "message" => "XSD warning"},
      %{"code" => "rule-1", "criticity" => "warning", "message" => "Base rule warning"}
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

  @doc "Report for XSD-specific rendering tests — xsd-schema category, empty issue page"
  def netex_validation_details_for_xsd(opts \\ []) do
    defaults = [
      has_errors?: true,
      max_severity: %{"max_level" => "error", "worst_occurrences" => 3},
      summary: [%{"category" => "xsd-schema", "stats" => %{"criticity" => "error", "count" => 1}}],
      issues_page: %Scrivener.Page{entries: []}
    ]

    netex_validation_details(Keyword.merge(defaults, opts))
  end

  @doc "v0.1.0 clean report (the CaseClauseError regression case)"
  def netex_validation_details_v0_1_0_clean(opts \\ []) do
    netex_validation_details(
      [
        adapter: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0,
        download_url: nil,
        has_errors?: false,
        max_severity: %{"max_level" => "NoError", "worst_occurrences" => 0},
        summary: [],
        stats: %{},
        issues_page: %Scrivener.Page{entries: []}
      ] ++ opts
    )
  end

  @doc "v0.2.x clean report with category tabs still visible"
  def netex_validation_details_v0_2_x_clean(opts \\ []) do
    netex_validation_details(
      [
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
      ] ++ opts
    )
  end

  @doc "Report with error+warning severity errors across XSD and base-rules categories"
  def netex_validation_details_with_errors(filter \\ %{}, opts \\ []) do
    netex_validation_details(
      [
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
            %{
              "criticity" => "error",
              "message" => "Test error",
              "resource" => %{"filename" => "test.xml", "line" => 42}
            }
          ])
      ] ++ opts
    )
  end

  @doc "Report with warning-only severity errors"
  def netex_validation_details_with_warnings(opts \\ []) do
    netex_validation_details(
      [
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
      ] ++ opts
    )
  end

  @doc "Report with information-only severity errors"
  def netex_validation_details_with_information(opts \\ []) do
    netex_validation_details(
      [
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
      ] ++ opts
    )
  end

  @doc "Report with unknown-location issues (nil resource, nil filename)"
  def netex_validation_details_unknown_location(filter \\ %{}, opts \\ []) do
    netex_validation_details(
      [
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
      ] ++ opts
    )
  end

  @doc "Report for testing French profile compliance (requires French Profile adapter)"
  def netex_validation_details_french_profile(compliance \\ :partial, opts \\ []) do
    netex_validation_details(
      [
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
      ] ++ opts
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
