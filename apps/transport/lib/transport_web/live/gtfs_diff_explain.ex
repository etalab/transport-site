defmodule TransportWeb.GTFSDiffExplain do
  @moduledoc """
  Functions to explain and interpret GTFS Diff files
  """
  use Gettext, backend: TransportWeb.Gettext

  def diff_explanations(diffs) do
    diffs
    |> Enum.flat_map(fn diff ->
      diff =
        diff
        |> Map.update("initial_value", %{}, &try_jason_decode(&1))
        |> Map.update("new_value", %{}, &try_jason_decode(&1))
        |> Map.update("identifier", %{}, &try_jason_decode(&1))

      []
      |> explanation_add_file(diff)
      |> explanation_delete_file(diff)
      |> explanation_update_stop_name(diff)
      |> explanation_stop_wheelchair_access(diff)
    end)
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
      dgettext("validations", ~s(A file named "%{file}" has been added), file: file)
      | explanations
    ]
  end

  def explanation_add_file(explanations, _), do: explanations

  def explanation_delete_file(explanations, %{
        "action" => "delete",
        "file" => file,
        "target" => "file"
      }) do
    [dgettext("validations", ~s(The file "%{file}" has been deleted), file: file) | explanations]
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
      dgettext(
        "validations",
        ~s([stops.txt] The name of the stop_id %{stop_id} has been modified. Initial name: "%{initial_stop_name}", New name: "%{new_stop_name}"),
        stop_id: stop_id,
        initial_stop_name: initial_stop_name,
        new_stop_name: new_stop_name
      )
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
      dgettext(
        "validations",
        ~s([stops.txt] Wheelchair_boarding information added for stop_id %{stop_id}, previously: "%{initial_wheelchair_boarding}", now: "%{new_wheelchair_boarding}"),
        stop_id: stop_id,
        initial_wheelchair_boarding: initial_wheelchair_boarding,
        new_wheelchair_boarding: new_wheelchair_boarding
      )
      | explanations
    ]
  end

  def explanation_stop_wheelchair_access(explanations, _), do: explanations

  def try_jason_decode(""), do: nil
  def try_jason_decode(input), do: Jason.decode!(input)
end
