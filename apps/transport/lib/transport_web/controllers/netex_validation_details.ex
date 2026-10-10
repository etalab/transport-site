defmodule TransportWeb.NeTExValidationDetails do
  @moduledoc """
  Encapsulates all data needed to render a NeTEx validation page.

  Meant to be used to display in views and isolate logic or data transformations.
  Handles pagination and results adapters calling.
  """

  alias DB.MultiValidation
  alias Transport.Validators.NeTEx.ResultsAdapter
  alias Transport.Validators.NeTEx.ResultsAdapters.Commons

  @type t :: %__MODULE__{
          adapter: ResultsAdapter.t(),
          summary: list(map()) | nil,
          stats: map() | nil,
          metadata: map(),
          modes: [String.t()],
          filter: map(),
          issues_page: Scrivener.Page.t(),
          max_severity: map() | nil,
          xsd_errors: list(),
          validator_version: String.t() | nil,
          category_severity_counts: map()
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
            validator_version: nil,
            category_severity_counts: %{}

  @doc """
  Builds a complete NeTExValidationDetails from a validation record.

  This datatype is meant to be used for display in views without logic.
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
    df = Commons.from_binary(binary_result)

    {filter, {total_entries, entries}} = adapter.get_issues(df, params, config)
    issues_page = paginate_netex_results({total_entries, entries}, config)

    %__MODULE__{
      adapter: adapter,
      summary: adapter.summary_by_category(df),
      stats: digest["stats"],
      metadata: metadata.metadata,
      modes: metadata.modes,
      filter: filter,
      issues_page: issues_page,
      max_severity: digest["max_severity"],
      xsd_errors: adapter.summarize_xsd_errors(df),
      validator_version: version,
      category_severity_counts: adapter.count_by_category_and_severity(df)
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
