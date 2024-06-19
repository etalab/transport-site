import Ecto.Query

ids_with_heterogeneous_modes = [614, 362, 146]

defmodule CounterCache do
  @doc """
  Retrieves one line per "resource <-> modes" with its dataset (for GTFS resources only).
  """
  def resources_with_modes(optional_dataset_ids \\ nil) do
    DB.Dataset.base_query()
    |> maybe_where(optional_dataset_ids)
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> select([dataset: d, resource: r, metadata: m], {d.id, r.id, m.modes})
    |> DB.Repo.all()
  end

  def maybe_where(query, nil), do: query
  def maybe_where(query, dataset_ids), do: query |> where([dataset: d], d.id in ^dataset_ids)
end

CounterCache.resources_with_modes(ids_with_heterogeneous_modes)
|> IO.inspect(IEx.inspect_opts() |> Keyword.merge(limit: :infinity))
