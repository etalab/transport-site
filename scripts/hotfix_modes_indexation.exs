import Ecto.Query

ids_with_heterogeneous_modes = [614, 362, 146]

defmodule CounterCache do
  @doc """
  Retrieves one line per "dataset <-> resource <-> metadata" join, for GTFS resources only.
  """
  def datasets_with_modes_db(optional_dataset_ids \\ nil) do
    DB.Dataset.base_query()
    |> maybe_where(optional_dataset_ids)
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> select([dataset: d, resource: r, metadata: m], {d.id, m.modes})
    |> DB.Repo.all()
  end

  def maybe_where(query, nil), do: query
  def maybe_where(query, ids), do: query |> where([dataset: d], d.id in ^ids)

  @doc """
  Grouped by dataset, return a sorted, deduped list of modes.
  """
  def datasets_with_modes(optional_dataset_ids \\ nil) do
    datasets_with_modes_db(optional_dataset_ids)
    |> Enum.group_by(fn {d_id, modes} -> d_id end, fn {d_id, modes} -> modes end)
    |> Enum.map(fn {d_id, modes} -> {d_id, modes |> List.flatten() |> Enum.sort() |> Enum.uniq()} end)
    |> Enum.sort_by(fn {d_id, _modes} -> d_id end)
  end
end

CounterCache.datasets_with_modes_db(ids_with_heterogeneous_modes)
|> IO.inspect(IEx.inspect_opts() |> Keyword.merge(limit: :infinity))

CounterCache.datasets_with_modes(ids_with_heterogeneous_modes)
|> IO.inspect(IEx.inspect_opts() |> Keyword.merge(limit: :infinity))
