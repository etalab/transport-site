defmodule Transport.Jobs.CleanOnDemandValidationJob do
  @moduledoc """
  This job is in charge of archiving on-demand-related `DB.MultiValidation` records after a given period.

  For on-demand rows older than `@days_before_archiving` days, we remove the validation
  result and its visualization.
  """
  use Oban.Worker, unique: [period: :infinity], max_attempts: 3
  import Ecto.Query

  @days_before_archiving 30

  def retention_days, do: @days_before_archiving

  # General case: enqueue days to archive
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when is_nil(args) or args == %{} do
    days_to_archive()
    |> Enum.with_index()
    |> Enum.map(fn {date, index} -> %{date: date} |> new(schedule_in: index * 60) end)
    |> Oban.insert_all()

    :ok
  end

  # Archive rows for a specific day
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"date" => date}}) do
    date = Date.from_iso8601!(date)

    if Date.compare(date, Date.utc_today() |> Date.add(-@days_before_archiving)) == :gt do
      {:cancel, "Cannot archive rows if they are not older than #{@days_before_archiving} days"}
    else
      multi_validation_in_scope()
      |> where([mv], fragment("?::date = ?", mv.inserted_at, ^date))
      |> update([mv], set: [result: nil, data_vis: nil])
      |> DB.Repo.update_all([])

      :ok
    end
  end

  def days_to_archive do
    limit_date = DateTime.utc_now() |> DateTime.add(-@days_before_archiving, :day)

    multi_validation_in_scope()
    |> where([mv], mv.inserted_at <= ^limit_date)
    |> select([mv], fragment("?::date", mv.inserted_at))
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.sort()
  end

  defp multi_validation_in_scope do
    DB.MultiValidation.base_query()
    # is an on-demand validation
    |> where([mv], not is_nil(mv.oban_args) and is_nil(mv.resource_id) and is_nil(mv.resource_history_id))
    # has not been cleaned yet
    |> where([mv], not is_nil(mv.result))
  end
end
