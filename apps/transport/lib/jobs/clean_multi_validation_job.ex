defmodule Transport.Jobs.CleanMultiValidationJob do
  @moduledoc """
  This job is in charge of archiving `DB.MultiValidation` records.

  It keeps the 3 most recent records per resource ID, other records
  have their `result` and `data_vis` fields set to `null`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @max_records 1_000
  @next_job_dispatch {5, :second}
  @records_to_keep_per_resource 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    max_records = max_records()

    ids =
      subquery(
        DB.MultiValidation.base_query()
        |> where([mv], not is_nil(mv.resource_id))
        |> select([mv], %{
          id: mv.id,
          row_number: row_number() |> over(partition_by: mv.resource_id, order_by: {:desc, mv.inserted_at})
        })
      )
      |> select([t], t.id)
      |> where([t], t.row_number > @records_to_keep_per_resource)
      |> order_by([t], {:asc, t.id})
      |> limit(^max_records)
      |> DB.Repo.all()

    DB.MultiValidation.base_query()
    |> where([mv], mv.id in ^ids)
    |> update([mv], set: [result: nil, data_vis: nil])
    |> DB.Repo.update_all([])

    # We handled `max_records`. We've got more rows to handle, schedule another job
    if Enum.count(ids) == max_records do
      new(%{}, schedule_in: @next_job_dispatch) |> Oban.insert!()
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
end
