defmodule Transport.Validators.NeTEx.ResultsAdapter do
  @moduledoc """
  Interface for result adapters: helpers designed to interpret results of NeTEx validation.
  """

  @callback summary(map()) :: list()
  @callback count_by_severity(map()) :: map()
  @callback get_issues(map(), map()) :: list()
  @callback issue_type(list()) :: nil | binary()
  @callback format_severity(binary(), non_neg_integer()) :: binary()
  @callback count_max_severity(map()) :: {binary(), integer()}
  @callback no_error?(binary()) :: boolean()

  def resolve(_), do: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0
end
