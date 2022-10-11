defmodule Transport.Jobs.RemoveHistoryJob do
  @moduledoc """
  This job removes `DB.ResourceHistory` rows and deletes S3 objects for a given dataset type or a dataset ID.

  This can be used to clean historicized resources that should not exist anymore.
  """
  import Ecto.Query
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_type" => dataset_type}}) do
    DB.Dataset
    |> where([d], d.type == ^dataset_type)
    |> DB.Repo.all()
    |> Enum.filter(&DB.Dataset.should_skip_history?/1)
    |> Enum.map(&__MODULE__.new(%{"dataset_id" => &1.id}))
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) when is_integer(dataset_id) do
    if DB.Dataset.should_skip_history?(DB.Repo.get!(DB.Dataset, dataset_id)) do
      objects =
        DB.ResourceHistory
        |> where([rh], fragment("cast(payload->>'dataset_id' as bigint) = ?", ^dataset_id))
        |> DB.Repo.all()

      ids = objects |> Enum.map(& &1.id)

      mark_for_deletion(ids)
      remove_s3_objects(objects |> Enum.map(&Map.fetch!(&1.payload, "filename")))
      remove_resource_history_rows(ids)

      :ok
    else
      {:discard, "Cannot remove history rows for dataset##{dataset_id} because it should not be skipped"}
    end
  end

  defp mark_for_deletion(ids) do
    DB.ResourceHistory
    |> where([r], r.id in ^ids)
    |> update(set: [payload: fragment("jsonb_set(payload, '{mark_for_deletion}', 'true')")])
    |> DB.Repo.update_all([])
  end

  defp remove_resource_history_rows(ids) do
    DB.ResourceHistory |> where([r], r.id in ^ids) |> DB.Repo.delete_all()
  end

  defp remove_s3_objects(paths) do
    paths |> Enum.each(&Transport.S3.delete_object!(:history, &1))
  end
end
