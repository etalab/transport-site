defmodule Transport.CounterCache do
  @moduledoc """
  This module is responsible for updating the `counter_cache` field of the `resources` table.
  """

  import Ecto.Query

  @doc """
  Take all the (GTFS) resources with at least one associated GTFS metadata, and
  update the `counter_cache` columns with modes information. This is done to avoid
  costly runtime joins.
  """
  def cache_modes_on_resources() do
    resources_with_modes()
    |> prepare_update_values()
    |> DB.Repo.all()
    |> apply_all_updates!()
  end

  # Build the query to retrieve one line per "resource <-> modes" with its dataset (for GTFS resources only).
  @spec resources_with_modes() :: Ecto.Query.t()
  defp resources_with_modes() do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
  end

  # Prepare a list of maps compatible with a bulk values update (https://hexdocs.pm/ecto/Ecto.Query.API.html#values/2)
  @spec prepare_update_values(Ecto.Query.t()) :: Ecto.Query.t()
  defp prepare_update_values(query) do
    query
    |> select([resource: r, metadata: m], %{resource_id: r.id, resource_gtfs_modes: m.modes})
  end

  # Given a list of planned updates, for each resource, in batch, update the `counter_cache`
  # field to contain a JSONB map with `gtfs_modes` array. Example of SQL generated:
  #
  # ```sql
  # UPDATE "resource" AS r
  # SET "counter_cache" = jsonb_build_object('gtfs_modes', v."resource_gtfs_modes")
  # FROM (
  #   VALUES (ARRAY['tramway'], 80705), (ARRAY['bus', 'funicular'], 80223)
  # ) AS v ("resource_gtfs_modes", "resource_id")
  # WHERE r."id" = v."resource_id";
  # ```
  @type update_resource_modes_list :: [%{resource_id: integer(), resource_gtfs_modes: [String.t()]}]
  @spec apply_all_updates!(update_resource_modes_list) :: any()
  defp apply_all_updates!(updates) do
    types = %{resource_id: :integer, resource_gtfs_modes: {:array, :string}}

    from(r in DB.Resource,
      join: u in values(updates, types),
      on: r.id == u.resource_id,
      update: [set: [counter_cache: fragment("jsonb_build_object('gtfs_modes', ?)", u.resource_gtfs_modes)]]
    )
    |> DB.Repo.update_all([])
  end
end
