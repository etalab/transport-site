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
          filter: map(),
          issues_page: Scrivener.Page.t(),
          max_severity: String.t() | nil,
          xsd_errors: list(),
          validator_version: String.t() | nil
        }

  defstruct adapter: nil,
            summary: nil,
            stats: nil,
            metadata: %{},
            modes: [],
            filter: %{},
            issues_page: %Scrivener.Page{
              entries: [],
              page_number: 1,
              page_size: 0,
              total_entries: 0,
              total_pages: 0
            },
            max_severity: nil,
            xsd_errors: [],
            validator_version: nil

  @doc """
  Builds a complete NeTExValidationDetails from a validation record.

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

    {filter, {total_entries, entries}} = adapter.get_issues(binary_result, params, config)
    issues_page = paginate_netex_results({total_entries, entries}, config)

    %__MODULE__{
      adapter: adapter,
      summary: digest["summary"],
      stats: digest["stats"],
      metadata: metadata.metadata,
      modes: metadata.modes,
      filter: filter,
      issues_page: issues_page,
      max_severity: digest["max_severity"],
      xsd_errors: adapter.summarize_xsd_errors(binary_result),
      validator_version: version
    }
  end

  @doc """
  For NeTEx results we avoid loading every entries. We emulate
  Scrivener.paginate based on the total count.
  """
  def paginate_netex_results({total_entries, issues}, config) do
    total_pages = div(total_entries, config.page_size)

    total_pages =
      if rem(total_entries, config.page_size) > 0 do
        total_pages + 1
      else
        total_pages
      end

    %Scrivener.Page{
      entries: issues,
      page_number: config.page_number,
      page_size: config.page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  def download_validation_report?(%DB.MultiValidation{binary_result: nil}, _max_severity), do: false
  def download_validation_report?(_binary_result, %{"max_level" => "NoError"}), do: false
  def download_validation_report?(_binary_result, _max_severity), do: true
end
