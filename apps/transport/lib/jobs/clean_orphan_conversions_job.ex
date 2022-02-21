defmodule Transport.Jobs.CleanOrphanConversionsJob do
  @moduledoc """
  Job in charge of clean `DB.DataConversion` rows
  where the underlying `DB.ResourceHistory` does not exist.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{DataConversion, Repo}

  @max_objects 500

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    objects =
      DataConversion
      |> where([_d], fragment("resource_history_uuid not in (select (payload->>'uuid')::uuid from resource_history)"))
      |> limit(@max_objects)
      |> Repo.all()

    ids = objects |> Enum.map(& &1.id)
    paths = objects |> Enum.map(&Map.fetch!(&1.payload, "filename"))

    mark_for_deletion(ids)
    remove_s3_objects(paths)
    remove_rows(ids)

    if Enum.count(objects) == @max_objects do
      %{} |> __MODULE__.new() |> Oban.insert!()
    end

    :ok
  end

  defp mark_for_deletion(ids) do
    DataConversion
    |> where([r], r.id in ^ids)
    |> update(set: [payload: fragment("jsonb_set(payload, '{mark_for_deletion}', 'true')")])
    |> Repo.update_all([])
  end

  defp remove_rows(ids) do
    DataConversion |> where([r], r.id in ^ids) |> Repo.delete_all()
  end

  defp remove_s3_objects(paths) do
    paths |> Enum.each(&Transport.S3.delete_object!(:history, &1))
  end
end
