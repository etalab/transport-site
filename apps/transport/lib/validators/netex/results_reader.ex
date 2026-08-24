defmodule Transport.Validators.NeTEx.ResultsReader do
  @moduledoc """
  Interface for result readers: helpers designed to interpret results of NeTEx validation.
  """

  @callback get_issues(binary(), map(), Scrivener.Config.t()) :: {map(), {pos_integer(), list()}}
  @callback issue_type(list()) :: nil | binary()
  @callback format_severity(binary(), non_neg_integer()) :: binary()
  @callback no_error?(binary()) :: boolean()
  @callback french_profile_compliance_check() :: :none | :partial | :good_enough
  @callback french_profile() :: nil | module()
  @callback preferred_category_order() :: [binary()]
  @callback summarize_xsd_errors(binary()) :: list()

  def resolve("0.2.2"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_2
  def resolve("0.2.1"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_1
  def resolve("0.2.0"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0
  def resolve(_), do: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0
end
