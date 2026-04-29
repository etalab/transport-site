defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_2 do
  @moduledoc """
  ResultsAdapter implementation for version 0.2.2.
  """

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_1, as: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile_compliance_check, do: :partial

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile, do: Transport.NeTEx.FrenchProfile.V2

  # Following functions are all delegated to V0_2_1

  @spec get_max_severity_error(map()) :: binary()
  defdelegate get_max_severity_error(validation_result), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_max_severity(validation_result), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate no_error?(severity), to: Previous

  @spec severity_level(binary()) :: integer()
  defdelegate severity_level(key), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate format_severity(key, count), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_by_severity(validation_result), to: Previous

  defdelegate index_messages(messages), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate summary(validation_result), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate issue_type(list), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate get_issues(binary, filter, pagination_config), to: Previous

  defdelegate get_categories(df), to: Previous

  defdelegate pick_default_category(df, categories_preferred_order), to: Previous

  defdelegate order_issues_by_location(issues), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate digest(validation_result), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate to_dataframe(errors), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate to_binary_result(result), to: Previous

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate summarize_xsd_errors(binary_result), to: Previous
end
