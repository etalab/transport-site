defmodule Script do
  require Logger
  import Ecto.Query

  alias Transport.Validators.NeTEx.Validator
  alias Transport.Validators.NeTEx.MetadataExtractor

  def backfill_all(resource_ids \\ []) do
    load_candidates(resource_ids)
    |> Enum.each(fn [rh_id, rm_id] ->
      resource_history = DB.ResourceHistory |> DB.Repo.get(rh_id)
      resource_metadata = DB.ResourceMetadata |> DB.Repo.get(rm_id)
      backfill(resource_history, resource_metadata)
    end)

    Logger.info("Done")
  end

  defp load_candidates(resource_ids) do
    from(rm in DB.MultiValidation)
    |> join(:left, [mv, rh], rh in DB.ResourceHistory, on: mv.resource_history_id == rh.id)
    |> join(:left, [_mv, rh, r], r in DB.Resource, on: rh.resource_id == r.id)
    |> join(:left, [mv, _rh, _r, rm], rm in DB.ResourceMetadata, on: rm.multi_validation_id == mv.id)
    |> where([_mv, _rh, r, _rm], r.format == "NeTEx")
    |> where([mv, _rh, _r, _rm], mv.validator == "enroute-chouette-netex-validator")
    |> where([_mv, _rh, _r, rm], fragment("?->>'start_date' is null", rm.metadata))
    |> select([_mv, rh, _r, rm], [rh.id, rm.id])
    |> order_by([_mv, _rh, _r, rm], {:asc, rm.updated_at})
    |> filter(resource_ids)
    |> DB.Repo.all()
    |> log_count()
  end

  defp filter(query, resource_ids) do
    case resource_ids || [] do
      [] ->
        Logger.info("Backfilling metadata for NeTEx resources without validity dates")
        query

      _ ->
        Logger.info(
          "Backfilling metadata for NeTEx resources without validity dates, limited to resources #{inspect(resource_ids)}"
        )

        query |> where([_mv, _rh, r, _rm], r.id in ^resource_ids)
    end
  end

  defp log_count(candidates) do
    Logger.info("#{length(candidates)} candidates")

    candidates
  end

  defp backfill(%DB.ResourceHistory{} = resource_history, %DB.ResourceMetadata{} = resource_metadata) do
    Validator.with_resource_file(resource_history, fn filepath ->
      Logger.info("ResourceHistory##{resource_history.id} - ResourceMetadata##{resource_metadata.id} - #{filepath}")
      metadata = MetadataExtractor.extract(filepath)

      resource_metadata
      |> Ecto.Changeset.change(metadata: Map.merge(resource_metadata.metadata, metadata))
      |> DB.Repo.update!()
    end)
  end
end

Logger.configure(level: :info)
Script.backfill_all()
