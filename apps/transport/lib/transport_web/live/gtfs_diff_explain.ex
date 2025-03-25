defmodule TransportWeb.GTFSDiffExplain do
  @moduledoc """
  Functions to explain and interpret GTFS Diff files
  """
  import TransportWeb.Gettext

  def diff_explanations(diffs) do
    diffs
    |> Enum.flat_map(fn diff ->
      diff =
        diff
        |> Map.update("initial_value", %{}, &try_jason_decode(&1))
        |> Map.update("new_value", %{}, &try_jason_decode(&1))
        |> Map.update("identifier", %{}, &try_jason_decode(&1))

      []
      |> explanation_update_stop_name(diff)
      |> explanation_stop_wheelchair_access(diff)
      |> explanation_update_stop_longitude(diff)
      |> explanation_update_stop_latitude(diff)
    end)
  end

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

  @doc """
  Creates a summary of a given GTFS Diff

  iex> [
  ...> %{
  ...>   "action" => "delete",
  ...>   "file" => "agency.txt",
  ...>   "target" => "file"
  ...> },
  ...> %{
  ...>   "action" => "delete",
  ...>   "file" => "calendar.txt",
  ...>   "target" => "column"
  ...> },
  ...> %{
  ...>   "action" => "add",
  ...>   "file" => "stop_times.txt",
  ...>   "target" => "row"
  ...> }] |> diff_summary()
  %{
    "add" => [{{"stop_times.txt", "add", "row"}, 1}],
    "delete" => [
      {{"agency.txt", "delete", "file"}, 1},
      {{"calendar.txt", "delete", "column"}, 1},
    ]
  }
  """
  def diff_summary(diff) do
    order = %{"file" => 0, "column" => 1, "row" => 2}

    diff
    |> Enum.frequencies_by(fn r ->
      {Map.get(r, "file"), Map.get(r, "action"), Map.get(r, "target")}
    end)
    |> Enum.sort_by(fn {{_, _, target}, _} -> order |> Map.fetch!(target) end)
    |> Enum.group_by(fn {{_file, action, _target}, _n} -> action end)
  end

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

  def explanation_update_stop_name(
        explanations,
        %{
          "action" => "update",
          "file" => "stops.txt",
          "target" => "row",
          "identifier" => %{"stop_id" => stop_id},
          "new_value" => %{"stop_name" => new_stop_name},
          "initial_value" => %{"stop_name" => initial_stop_name}
        }
      ) do
    [
      {"stops.txt", "stop_name",
       dgettext(
         "validations",
         ~s(The name of the stop_id %{stop_id} has been modified. Initial name: "%{initial_stop_name}", New name: "%{new_stop_name}"),
         stop_id: stop_id,
         initial_stop_name: initial_stop_name,
         new_stop_name: new_stop_name
       )}
      | explanations
    ]
  end

  def explanation_update_stop_name(explanations, _) do
    explanations
  end

  def explanation_stop_wheelchair_access(
        explanations,
        %{
          "action" => "update",
          "file" => "stops.txt",
          "target" => "row",
          "identifier" => %{"stop_id" => stop_id},
          "new_value" => %{"wheelchair_boarding" => new_wheelchair_boarding},
          "initial_value" => %{"wheelchair_boarding" => initial_wheelchair_boarding}
        }
      )
      when new_wheelchair_boarding in ["1", "2"] do
    [
      {"stops.txt", "wheelchair_boarding",
       dgettext(
         "validations",
         ~s(Wheelchair_boarding information added for stop_id %{stop_id}, previously: "%{initial_wheelchair_boarding}", now: "%{new_wheelchair_boarding}"),
         stop_id: stop_id,
         initial_wheelchair_boarding: initial_wheelchair_boarding,
         new_wheelchair_boarding: new_wheelchair_boarding
       )}
      | explanations
    ]
  end

  def explanation_stop_wheelchair_access(explanations, _), do: explanations

  def explanation_update_stop_longitude(
        explanations,
        %{
          "action" => "update",
          "file" => "stops.txt",
          "target" => "row",
          "identifier" => %{"stop_id" => stop_id},
          "new_value" => %{"stop_lon" => new_stop_lon},
          "initial_value" => %{"stop_lon" => initial_stop_lon}
        }
      ) do
    [
      {"stops.txt", "stop_lon",
       dgettext(
         "validations",
         ~s(The longitude of the stop_id %{stop_id} has been modified. "%{initial_stop_lon}" -> "%{new_stop_lon}"),
         stop_id: stop_id,
         initial_stop_lon: initial_stop_lon,
         new_stop_lon: new_stop_lon
       )}
      | explanations
    ]
  end

  def explanation_update_stop_longitude(explanations, _) do
    explanations
  end

  def explanation_update_stop_latitude(
        explanations,
        %{
          "action" => "update",
          "file" => "stops.txt",
          "target" => "row",
          "identifier" => %{"stop_id" => stop_id},
          "new_value" => %{"stop_lat" => new_stop_lat},
          "initial_value" => %{"stop_lat" => initial_stop_lat}
        }
      ) do
    [
      {"stops.txt", "stop_lat",
       dgettext(
         "validations",
         ~s(The latitude of the stop_id %{stop_id} has been modified. "%{initial_stop_lat}" -> "%{new_stop_lat}"),
         stop_id: stop_id,
         initial_stop_lat: initial_stop_lat,
         new_stop_lat: new_stop_lat
       )}
      | explanations
    ]
  end

  def explanation_update_stop_latitude(explanations, _) do
    explanations
  end

  def try_jason_decode(""), do: nil
  def try_jason_decode(input), do: Jason.decode!(input)
end
