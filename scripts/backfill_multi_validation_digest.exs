defmodule Script do
  require Logger
  import Ecto.Query

  def backfill_all do
    Logger.info("Backfilling digests")

    from(mv in DB.MultiValidation)
    |> select([mv], [mv.id])
    |> where([mv], not is_nil(mv.result))
    |> where([mv], is_nil(mv.digest))
    |> DB.Repo.all()
    |> Enum.each(fn [mv_id] ->
      DB.MultiValidation.with_result() |> DB.Repo.get(mv_id) |> backfill_multi_validation()
    end)

    Logger.info("Done")
  end

  def backfill_multi_validation(%DB.MultiValidation{result: nil, digest: nil} = mv) do
    Logger.warning("No result for multi_validation ##{mv.id}")
  end

  def backfill_multi_validation(%DB.MultiValidation{validator: validator, digest: nil} = mv) do
    Logger.info("Processing multi_validation ##{mv.id} - #{validator}")

    case validator do
      "GTFS transport-validator" ->
        Transport.Validators.GTFSTransport.digest(mv.result)

      "gtfs-realtime-validator" ->
        Transport.Validators.GTFSRT.digest(mv.result)

      "enroute-chouette-netex-validator" ->
        Transport.Validators.NeTEx.ResultsAdapter.resolve(mv.validator_version).digest(mv.result)

      "MobilityData/gbfs-validator" ->
        Transport.Validators.GBFSValidator.digest(mv.result)

      "GBFS-Validator" ->
        Transport.Validators.GBFSValidator.digest(mv.result)

      "validata-api" ->
        Transport.Validators.TableSchema.digest(mv.result)

      "validata" ->
        Transport.Validators.TableSchema.digest(mv.result)

      "Validata JSON" ->
        Transport.Validators.ValidataJson.digest(mv.result)

      "EXJSONSchema" ->
        Transport.Validators.EXJSONSchema.digest(mv.result)

      "ExJsonSchema" ->
        Transport.Validators.EXJSONSchema.digest(mv.result)

      unsupported ->
        Logger.warning("multi_validation ##{mv.id}: unsupported validator #{unsupported}")
        nil
    end
    |> save(mv)
  end

  def backfill_multi_validation(%DB.MultiValidation{} = mv) do
    Logger.info("Skipping multi_validation ##{mv.id}")
  end

  defp save(nil, _mv) do
  end

  defp save(digest, mv) do
    mv
    |> Ecto.Changeset.change(digest: digest)
    |> DB.Repo.update!()
  end
end

Logger.configure(level: :info)
Script.backfill_all()
