defmodule Transport.GTFSImportStops do
  @moduledoc """
  A module to import stops in a single `DB.DataImport` for a given resource, based on `resource_history_id`.
  """

  import Ecto.Query

  @doc """
  For the given `resource_history_id`, imports stops and agencies in a new `DB.DataImport`, then delete all related
  pre-existing `DB.DataImport` (either with the same `resource_history_id`, or for the same resource).
  """
  def import_stops_and_remove_previous(resource_history_id) do
    # Transaction timeout is at 15s currently, we may need to customize this here later
    {:ok, data_import_id} =
      DB.Repo.transaction(fn ->
        data_import_id =
          Transport.Jobs.GtfsToDB.import_gtfs_from_resource_history(resource_history_id, :stops_and_agencies)

        resource_id = DB.Repo.get_by(DB.ResourceHistory, id: resource_history_id).resource_id

        query =
          from(rh in DB.ResourceHistory,
            where: rh.resource_id == ^resource_id and rh.id != ^resource_history_id,
            select: rh.id
          )

        resource_history_ids = query |> DB.Repo.all()

        # NOTE: we may need to add an index on di.resource_history_id
        DB.DataImport
        # delete all previous data imports for the same resource history id
        |> where([di], di.resource_history_id == ^resource_history_id and di.id != ^data_import_id)
        # delete all previous data imports for the same resource but different resource history ids
        |> or_where([di], di.resource_history_id in ^resource_history_ids)
        |> DB.Repo.delete_all()

        data_import_id
      end)

    data_import_id
  end
end
