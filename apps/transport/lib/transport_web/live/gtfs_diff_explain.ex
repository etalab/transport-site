defmodule TransportWeb.GTFSDiffExplain do
  @moduledoc """
  Functions to explain and interpret GTFS Diff files
  """

  defdelegate diff_explanations(diffs), to: TransportWeb.GTFSDiffExplain.Explanations

  defdelegate diff_summary(diffs), to: TransportWeb.GTFSDiffExplain.Summary

  defdelegate structural_changes(diffs), to: TransportWeb.GTFSDiffExplain.StructuralChanges
end
