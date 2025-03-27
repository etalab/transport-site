defmodule TransportWeb.GTFSDiffExplain do
  @moduledoc """
  Functions to explain and interpret GTFS Diff files
  """
  use Gettext, backend: TransportWeb.Gettext

  defdelegate diff_explanations(diffs), to: TransportWeb.GTFSDiffExplain.Explanations

  defdelegate diff_summary(diffs), to: TransportWeb.GTFSDiffExplain.Summary

  defdelegate structural_changes(diffs), to: TransportWeb.GTFSDiffExplain.StructuralChanges

  def explanation_add_file(explanations, %{"action" => "add", "file" => file, "target" => "file"}) do
    [
      {file, dgettext("validations", ~s(A file named "%{file}" has been added), file: file)}
      | explanations
    ]
  end

  def explanation_add_file(explanations, _), do: explanations

  def explanation_delete_file(explanations, %{
        "action" => "delete",
        "file" => file,
        "target" => "file"
      }) do
    [{file, dgettext("validations", ~s(The file "%{file}" has been deleted), file: file)} | explanations]
  end

  def explanation_delete_file(explanations, _), do: explanations
end
