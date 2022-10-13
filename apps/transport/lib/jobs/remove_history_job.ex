defmodule Transport.Jobs.RemoveHistoryJob do
  @moduledoc """
  This job removes `DB.ResourceHistory` rows and deletes S3 objects for a given dataset type or a dataset ID.

  It does so in 2 steps:
  - it marks relevant rows up for deletion
  - the same job (but another `perform`) takes care of removing rows and deleting objects

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

  def perform(%Oban.Job{args: %{"action" => "remove", "dataset_id" => dataset_id} = args})
      when is_integer(dataset_id) do
    objects =
      DB.ResourceHistory
      |> where(
        [rh],
        fragment("payload \\? 'mark_for_deletion'") and
          fragment("cast(payload->>'dataset_id' as bigint) = ?", ^dataset_id)
      )
      |> limit(50)
      |> DB.Repo.all()

    unless Enum.empty?(objects) do
      remove_s3_objects(objects |> Enum.map(&Map.fetch!(&1.payload, "filename")))
      remove_resource_history_rows(objects |> Enum.map(& &1.id))
      args |> __MODULE__.new(schedule_in: 60 * 60 * 3) |> Oban.insert!()
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id} = args}) when is_integer(dataset_id) do
    if DB.Dataset.should_skip_history?(DB.Repo.get!(DB.Dataset, dataset_id)) do
      DB.ResourceHistory
      |> where([rh], fragment("cast(payload->>'dataset_id' as bigint) = ?", ^dataset_id))
      |> select([rh], rh.id)
      |> DB.Repo.all()
      |> mark_for_deletion()

      args |> Map.put("action", "remove") |> __MODULE__.new() |> Oban.insert!()

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
