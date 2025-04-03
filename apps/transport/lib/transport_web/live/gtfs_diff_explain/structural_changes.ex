defmodule TransportWeb.GTFSDiffExplain.StructuralChanges do
  @moduledoc """
  Functions to interpret structural changes of GTFS Diff files.
  """

  @doc """
  Analyses structural changes of diff, focusing on column changes and if the file has been created or deleted.

  It ignores the row changes.
  """
  def structural_changes(diffs) do
    Enum.reduce(diffs, %{}, fn action, acc ->
      if Map.get(action, "target") == "row" do
        acc
      else
        new_diff = structural_change(action)

        Map.update(acc, Map.get(action, "file"), [new_diff], &merge_diffs(new_diff, &1))
      end
    end)
  end

  defp structural_change(%{"target" => "file", "action" => action}) do
    case action do
      "add" -> :added_file
      "delete" -> :deleted_file
    end
  end

  defp structural_change(%{"target" => "column", "action" => action, "identifier" => identifier}) do
    %{"column" => column} = Jason.decode!(identifier)

    case action do
      "add" -> {:added_columns, [column]}
      "delete" -> {:deleted_columns, [column]}
    end
  end

  defp merge_diffs({column_action, _} = new_diff, diffs) do
    existing_action =
      Enum.find(diffs, fn elem ->
        case elem do
          {^column_action, _} -> true
          _ -> false
        end
      end)

    if existing_action do
      Enum.map(diffs, &merge_existing_actions(new_diff, &1))
    else
      [new_diff | diffs]
    end
  end

  defp merge_diffs(new_diff, diffs) do
    [new_diff | diffs]
  end

  defp merge_existing_actions({column_action, columns1}, elem) do
    case elem do
      {^column_action, columns2} -> {column_action, Enum.sort(columns1 ++ columns2)}
      _ -> elem
    end
  end
end
