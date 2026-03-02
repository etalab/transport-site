defmodule Script do
  require Logger
  import Ecto.Query

  alias Transport.Validators.NeTEx.Validator
  alias Transport.Validators.NeTEx.MetadataExtractor

  def backfill_all(resource_ids \\ []) do
    load_candidates(resource_ids)
    |> log_count()
    |> Enum.each(&backfill/1)

    Logger.info("Done")
  end

  defp load_candidates(resource_ids) do
    from_multi_validation_and_resource_metadata_for_historized_resources()
    |> is_netex()
    |> without_computed_validity_dates()
    |> limited_to_subset(resource_ids)
    |> oldest_first()
    |> DB.Repo.all()
  end

  def from_multi_validation_and_resource_metadata_for_historized_resources do
    from(rm in DB.MultiValidation)
    |> join(:left, [mv, rh], rh in DB.ResourceHistory, on: mv.resource_history_id == rh.id)
    |> join(:left, [_mv, rh, r], r in DB.Resource, on: rh.resource_id == r.id)
    |> join(:left, [mv, _rh, _r, rm], rm in DB.ResourceMetadata, on: rm.multi_validation_id == mv.id)
    |> select([_mv, rh, _r, rm], [rh.id, rm.id])
  end

  defp is_netex(query) do
    query
    |> where([_mv, _rh, r, _rm], r.format == "NeTEx")
    |> where([mv, _rh, _r, _rm], mv.validator == "enroute-chouette-netex-validator")
  end

  defp without_computed_validity_dates(query) do
    query
    |> where([_mv, _rh, _r, rm], fragment("?->>'start_date' is null", rm.metadata))
    |> where([_mv, _rh, _r, rm], not fragment("coalesce((?->>'no_validity_dates')::boolean, false)", rm.metadata))
  end

  defp limited_to_subset(query, resource_ids) do
    intro = "Backfilling metadata for NeTEx resources without validity dates"

    case resource_ids || [] do
      [] ->
        Logger.info(intro)
        query

      _ ->
        Logger.info("#{intro}, limited to resources #{inspect(resource_ids)}")
        query |> where([_mv, _rh, r, _rm], r.id in ^resource_ids)
    end
  end

  def oldest_first(query) do
    order_by(query, [_mv, _rh, _r, rm], {:asc, rm.updated_at})
  end

  defp log_count(candidates) do
    Logger.info("#{length(candidates)} candidates")

    candidates
  end

  defp backfill([rh_id, rm_id]) do
    resource_history = DB.ResourceHistory |> DB.Repo.get(rh_id)
    resource_metadata = DB.ResourceMetadata |> DB.Repo.get(rm_id)
    backfill(resource_history, resource_metadata)
  end

  defp backfill(%DB.ResourceHistory{} = resource_history, %DB.ResourceMetadata{} = resource_metadata) do
    Validator.with_resource_file(resource_history, fn filepath ->
      Logger.info("ResourceHistory##{resource_history.id} - ResourceMetadata##{resource_metadata.id} - #{filepath}")
      metadata = MetadataExtractor.extract(filepath)

      modes = metadata["modes"] || []
      metadata = Map.merge(resource_metadata.metadata, metadata)

      resource_metadata
      |> Ecto.Changeset.change(metadata: metadata, modes: modes)
      |> DB.Repo.update!()
    end)
  end
end

Logger.configure(level: :info)
Script.backfill_all()
