defmodule Transport.Jobs.CleanMultiValidationJob do
  @moduledoc """
  This job is in charge of archiving `DB.MultiValidation` records.

  - For static resources, we keep the 3 most recent records per resource ID.
  - For real-time resources, we archive rows older than 30 days.

  Archived records have their `result` and `data_vis` fields set to `null`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @max_records 1_000
  @next_job_dispatch {5, :second}
  # For static resources
  @records_to_keep_per_resource 3
  # For real-time resources
  @days_to_keep_realtime_rows 30

  # Dispatch jobs for both cases
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when args == %{} do
    new(%{"static" => true}) |> Oban.insert!()
    new(%{"real_time" => true}) |> Oban.insert!()
    :ok
  end

  # Logic for static resources
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"static" => true} = job_args}) do
    max_records = max_records()

    inner_query =
      from(mv in DB.MultiValidation,
        join: rh in DB.ResourceHistory,
        on: rh.id == mv.resource_history_id,
        where: not is_nil(mv.result) and is_nil(mv.resource_id),
        select: %{
          id: mv.id,
          row_number: row_number() |> over(partition_by: rh.resource_id, order_by: {:desc, mv.inserted_at})
        }
      )

    ids =
      from(q in subquery(inner_query),
        where: q.row_number >= @records_to_keep_per_resource,
        select: q.id,
        order_by: {:asc, q.id},
        limit: ^max_records
      )
      |> DB.Repo.all()

    archive_records(ids)

    # We handled `max_records`. We've got more rows to handle, schedule another job
    if Enum.count(ids) == max_records do
      new(job_args, schedule_in: @next_job_dispatch) |> Oban.insert!()
    end

    :ok
  end

  # Logic for real-time resources
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"real_time" => true} = job_args}) do
    max_records = max_records()

    ids =
      from(mv in DB.MultiValidation,
        join: mv2 in DB.MultiValidation,
        on:
          mv2.resource_id == mv.resource_id and
            mv2.inserted_at <= datetime_add(mv.inserted_at, -@days_to_keep_realtime_rows, "day"),
        where: not is_nil(mv2.result) or not is_nil(mv2.binary_result),
        where: not is_nil(mv2.resource_id),
        order_by: {:asc, mv2.id},
        select: mv2.id,
        distinct: true,
        limit: ^max_records
      )
      |> DB.Repo.all()

    archive_records(ids)

    # We handled `max_records`. We've got more rows to handle, schedule another job
    if Enum.count(ids) == max_records do
      new(job_args, schedule_in: @next_job_dispatch) |> Oban.insert!()
    end

    :ok
  end

  def max_records do
    if Mix.env() == :test do
      1
    else
      @max_records
    end
  end

  defp archive_records(ids) do
    DB.MultiValidation.base_query()
    |> where([mv], mv.id in ^ids)
    |> update([mv], set: [binary_result: nil, result: nil, data_vis: nil])
    |> DB.Repo.update_all([])
  end
end
