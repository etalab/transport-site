defmodule NeTExTestData do
  @moduledoc """
  Shared test data for NeTEx validation controller tests.

  Used by both `ResourceControllerTest` and `ValidationControllerTest` to avoid
  duplicating result maps and multi-validation builder logic across the two files.
  """

  # Errors in both XSD and base-rules categories with mixed severities.
  # Used by category stats tests — summary_from_binary should report the worst
  # severity per category.
  def category_stats_result do
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
end
