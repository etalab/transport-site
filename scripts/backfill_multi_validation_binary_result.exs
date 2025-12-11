defmodule Script do
  @moduledoc """
  Script to backfill multi_validation.binary_result for NeTEx when result is available.
  """

  require Logger
  import Ecto.Query

  def backfill_all do
    Logger.info("Backfilling binary results")

    list_validations()
    |> Enum.each(fn [mv_id] -> process_validation(mv_id) end)

    Logger.info("Done")
  end

  defp list_validations do
    from(mv in DB.MultiValidation)
    |> select([mv], [mv.id])
    |> where([mv], not is_nil(mv.result))
    |> where([mv], is_nil(mv.binary_result))
    |> where([mv], mv.validator == "enroute-chouette-netex-validator")
    |> DB.Repo.all()
  end

  defp process_validation(mv_id) do
    DB.MultiValidation.with_result() |> DB.Repo.get(mv_id) |> backfill_binary_result_and_digest()
  end

  defp backfill_binary_result_and_digest(%DB.MultiValidation{result: nil, binary_result: nil} = mv) do
    Logger.warning("No result for multi_validation ##{mv.id}")
  end

  defp backfill_binary_result_and_digest(%DB.MultiValidation{binary_result: nil} = mv) do
    Logger.info("Processing multi_validation ##{mv.id}")

    mv
    |> Ecto.Changeset.change(build_changeset(mv))
    |> DB.Repo.update!()
  end

  defp backfill_binary_result_and_digest(%DB.MultiValidation{} = mv) do
    Logger.info("Skipping multi_validation ##{mv.id}")
  end

  defp build_changeset(%DB.MultiValidation{} = mv) do
    results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(mv.validator_version)

    binary_result = results_adapter.to_binary_result(mv.result)
    digest = results_adapter.digest(mv.result)

    %{binary_result: binary_result, digest: digest}
  end
end

Logger.configure(level: :info)
Script.backfill_all()
