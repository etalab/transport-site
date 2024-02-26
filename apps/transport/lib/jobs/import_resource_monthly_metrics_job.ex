defmodule Transport.Jobs.ImportResourceMonthlyMetricsJob do
  @moduledoc """
  Import monthly metrics related to resources coming from the data.gouv.fr's API.

  This job is executed daily and imports metrics for all resources.
  If resource metrics have not been imported previously, we well fetch metrics for the last 2 years.
  Otherwise we will fetch metrics only for the last 3 months.

  Records are not supposed to change in the past, except for the current month.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  # The number of workers to run in parallel when importing metrics
  @task_concurrency 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    resource_datagouv_ids()
    |> Task.async_stream(
      fn datagouv_id -> Transport.Jobs.ImportMonthlyMetrics.import_metrics(:resource, datagouv_id) end,
      max_concurrency: @task_concurrency,
      on_timeout: :kill_task,
      timeout: 10_000
    )
    |> Stream.run()
  end

  def resource_datagouv_ids do
    DB.Resource.base_query() |> select([resource: r], r.datagouv_id) |> DB.Repo.all()
  end
end
