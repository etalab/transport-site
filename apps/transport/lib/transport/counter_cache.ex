defmodule Transport.CounterCache do
  @moduledoc """
  This module is responsible for updating the `counter_cache` field of the `resources` table.
  """

  import Ecto.Query

  def cache_modes_on_resources do
    resources_with_modes()
    |> prepare_update_values()
    |> DB.Repo.all()
    # |> IO.inspect(IEx.inspect_opts() |> Keyword.merge(limit: :infinity))
    |> apply_all_updates!()
  end

  @doc """
  Build the query to retrieve one line per "resource <-> modes" with its dataset (for GTFS resources only).
  """
  @spec resources_with_modes([integer()] | nil) :: Ecto.Query.t()
  def resources_with_modes(optional_dataset_ids \\ nil) do
    DB.Dataset.base_query()
    |> maybe_where(optional_dataset_ids)
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
  end

  @doc """
  Prepare a list of maps compatible with a bulk values update (https://hexdocs.pm/ecto/Ecto.Query.API.html#values/2)
  """
  @spec prepare_update_values(Ecto.Query.t()) :: Ecto.Query.t()
  def prepare_update_values(query) do
    query
    |> select([resource: r, metadata: m], %{resource_id: r.id, resource_gtfs_modes: m.modes})
  end

  @doc """
  Given a list of planned updates, for each resource, in batch, update the `counter_cache`
  field to contain a JSONB map with `gtfs_modes` array.
  """
  @type update_resource_modes_list :: [%{resource_id: integer(), resource_gtfs_modes: [String.t()]}]
  @spec apply_all_updates!(update_resource_modes_list) :: any()
  def apply_all_updates!(updates) do
    types = %{resource_id: :integer, resource_gtfs_modes: {:array, :string}}

    from(r in DB.Resource,
      join: u in values(updates, types),
      on: r.id == u.resource_id,
      update: [set: [counter_cache: fragment("jsonb_build_object('gtfs_modes', ?)", u.resource_gtfs_modes)]]
    )
    |> DB.Repo.update_all([])
  end

  def maybe_where(query, nil), do: query
  def maybe_where(query, dataset_ids), do: query |> where([dataset: d], d.id in ^dataset_ids)
end
