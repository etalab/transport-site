defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_2 do
  @moduledoc """
  ResultsReader implementation for version 0.2.2.
  """

  alias Transport.Validators.NeTEx.ResultsReader
  alias Transport.Validators.NeTEx.ResultsWriter

  @behaviour ResultsReader
  @behaviour ResultsWriter

  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_1, as: Previous

  @impl ResultsReader
  def french_profile_compliance_check, do: :partial

  @impl ResultsReader
  def french_profile, do: Transport.NeTEx.FrenchProfile.V2

  @impl ResultsReader
  defdelegate preferred_category_order(), to: Previous

  @impl ResultsReader
  defdelegate no_error?(severity), to: Previous

  @impl ResultsReader
  defdelegate format_severity(key, count), to: Previous

  @impl ResultsReader
  defdelegate issue_type(list), to: Previous

  @impl ResultsReader
  defdelegate get_issues(binary, filter, pagination_config), to: Previous

  @impl ResultsReader
  defdelegate summarize_xsd_errors(binary_result), to: Previous

  @impl ResultsWriter
  defdelegate count_max_severity(df), to: Previous

  @impl ResultsWriter
  defdelegate get_max_severity_error(df), to: Previous

  @impl ResultsWriter
  defdelegate digest(df), to: Previous

  @impl ResultsWriter
  defdelegate to_dataframe(errors), to: Previous

  @impl ResultsWriter
  defdelegate to_binary_result(errors), to: Previous
end
