defmodule TransportWeb.NeTExValidationDetails do
  @moduledoc """
  Encapsulates all data needed to render a NeTEx validation page.

  Replaces the nested tuple pattern used in controllers with a single value object
  that carries both the adapter and all computed details.

  This provides **locality**: all build logic lives in one place, and callers access
  named fields instead of positional tuple elements. No new adapter callbacks are needed —
  it works with the existing interface plus Commons utilities.
  """

  alias DB.MultiValidation
  alias Transport.Validators.NeTEx.ResultsAdapter

  @type t :: %__MODULE__{
          adapter: ResultsAdapter.t(),
          summary: list(map()) | nil,
          stats: map() | nil,
          metadata: map(),
          modes: [String.t()],
          issues: {map(), {pos_integer(), list()}},
          max_severity: String.t() | nil,
          xsd_errors: list(),
          validator_version: String.t() | nil
        }

  defstruct adapter: nil,
            summary: nil,
            stats: nil,
            metadata: %{},
            modes: [],
            issues: {%{}, {0, []}},
            max_severity: nil,
            xsd_errors: [],
            validator_version: nil

  @doc """
  Builds a complete ValidationDetails from a validation record.

  Uses existing adapter methods (`get_issues/3`, `summarize_xsd_errors/1`) and
  Commons utilities — no new callbacks required.

  Returns an empty struct when the validation record is nil or incomplete,
  rather than `nil`. This avoids nil-checking in callers.
  """
  @spec build(MultiValidation.t() | nil, Scrivener.Config.t(), map()) :: t()
  def build(nil, _config, _params), do: %__MODULE__{}

  def build(%MultiValidation{binary_result: nil}, _config, _params), do: %__MODULE__{}

  def build(
        %MultiValidation{
          binary_result: binary_result,
          validator_version: version,
          metadata: metadata = %DB.ResourceMetadata{},
          digest: digest
        },
        config,
        params
      ) do
    adapter = ResultsAdapter.resolve(version)

    %__MODULE__{
      adapter: adapter,
      summary: digest["summary"],
      stats: digest["stats"],
      metadata: metadata.metadata,
      modes: metadata.modes,
      issues: adapter.get_issues(binary_result, params, config),
      max_severity: digest["max_severity"],
      xsd_errors: adapter.summarize_xsd_errors(binary_result),
      validator_version: version
    }
  end
end
