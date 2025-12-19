defmodule Transport.Validators.NeTEx.ResultsAdapter do
  @moduledoc """
  Interface for result adapters: helpers designed to interpret results of NeTEx validation.
  """

  @callback summary(map()) :: list()
  @callback count_by_severity(map()) :: map()
  @callback get_issues(binary(), map(), Scrivener.Config.t()) :: {map(), {pos_integer(), list()}}
  @callback digest(map()) :: map()
  @callback issue_type(list()) :: nil | binary()
  @callback format_severity(binary(), non_neg_integer()) :: binary()
  @callback count_max_severity(map()) :: {binary(), integer()}
  @callback no_error?(binary()) :: boolean()
  @callback french_profile_compliance_check() :: :none | :partial | :good_enough
  @callback to_dataframe(list()) :: Explorer.DataFrame.t()
  @callback to_binary_result(list()) :: binary()

  def resolve("0.2.1"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_1
  def resolve("0.2.0"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0
  def resolve(_), do: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0
end
