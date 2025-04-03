defmodule TransportWeb.GTFSDiffExplain.Summary do
  @moduledoc """
  Function to summarize GTFS Diff files
  """

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
end
