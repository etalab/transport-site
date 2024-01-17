defmodule Transport.Jobs.ImportDatasetMonthlyMetricsJob do
  @moduledoc """
  Import monthly metrics related to datasets coming from the data.gouv.fr's API.

  This job is executed daily and imports metrics for all datasets.
  If dataset metrics have not been imported previously, we well fetch metrics for the last 2 years.
  Otherwise we will fetch metrics only for the last 3 months.

  Records are not supposed to change in the past, except for the current month.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  # The number of workers to run in parallel when importing metrics
  @task_concurrency 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    dataset_datagouv_ids()
    |> Task.async_stream(
      fn datagouv_id -> Transport.Jobs.ImportMonthlyMetrics.import_metrics(:dataset, datagouv_id) end,
      max_concurrency: @task_concurrency,
      on_timeout: :kill_task,
      timeout: 10_000
    )
    |> Stream.run()
  end

  def dataset_datagouv_ids do
    DB.Dataset.base_query() |> select([dataset: d], d.datagouv_id) |> DB.Repo.all()
  end
end

defmodule Transport.Jobs.ImportMonthlyMetrics do
  @moduledoc """
  Shared methods to import monthly metrics from the data.gouv.fr's API.
  """
  require Logger
  import Ecto.Query

  # Maximum number of months to fetch for each model
  # 12*2 = 24 months
  @nb_records 12 * 2

  @doc """
  iex> api_url(:dataset, "datagouv_id", page_size: 24)
  "https://metric-api.data.gouv.fr/api/datasets/data/?dataset_id__exact=datagouv_id&page_size=24&metric_month__sort=desc"
  iex> api_url(:resource, "datagouv_id", page_size: 5)
  "https://metric-api.data.gouv.fr/api/resources/data/?resource_id__exact=datagouv_id&page_size=5&metric_month__sort=desc"
  """
  def api_url(model_name, datagouv_id, page_size: page_size) when model_name in [:dataset, :resource] do
    model_name
    |> api_base_url()
    |> URI.append_query(api_args(model_name, datagouv_id: datagouv_id, page_size: page_size))
    |> URI.to_string()
  end

  def import_metrics(model_name, datagouv_id) when model_name in [:dataset, :resource] do
    # If we already imported metrics for this model, fetch only the last 3 months
    url =
      if already_imported?(model_name, datagouv_id) do
        api_url(model_name, datagouv_id, page_size: 3)
      else
        api_url(model_name, datagouv_id, page_size: @nb_records)
      end

    case http_client().get(url, []) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        body
        |> Map.fetch!("data")
        |> Enum.each(fn data -> insert_or_update(model_name, datagouv_id, data) end)

      other ->
        Logger.error(
          "metric-api.data.gouv.fr unexpected HTTP response for #{model_name}##{datagouv_id}: #{inspect(other)}"
        )
    end
  end

  def already_imported?(:dataset, datagouv_id) do
    DB.DatasetMonthlyMetric |> where([d], d.dataset_datagouv_id == ^datagouv_id) |> DB.Repo.exists?()
  end

  def already_imported?(:resource, datagouv_id) do
    DB.ResourceMonthlyMetric |> where([d], d.resource_datagouv_id == ^datagouv_id) |> DB.Repo.exists?()
  end

  defp insert_or_update(model_name, datagouv_id, %{"metric_month" => metric_month} = data)
       when model_name in [:dataset, :resource] do
    Enum.each(metrics(model_name, data), fn {metric_name, count} ->
      count = count || 0

      model_name
      |> changeset(%{
        datagouv_id: datagouv_id,
        year_month: metric_month,
        metric_name: metric_name,
        count: count
      })
      |> DB.Repo.insert!(
        conflict_target: [String.to_existing_atom("#{model_name}_datagouv_id"), :year_month, :metric_name],
        on_conflict: [set: [count: count, updated_at: DateTime.utc_now()]]
      )
    end)
  end

  defp metrics(:dataset, %{
         "monthly_visit" => monthly_visit,
         "monthly_download_resource" => monthly_download_resource
       }) do
    [{:views, monthly_visit}, {:downloads, monthly_download_resource}]
  end

  defp metrics(:resource, %{"monthly_download_resource" => monthly_download_resource}) do
    [{:downloads, monthly_download_resource}]
  end

  defp changeset(:dataset, %{datagouv_id: datagouv_id} = params) do
    params = Map.put(params, :dataset_datagouv_id, datagouv_id)
    DB.DatasetMonthlyMetric.changeset(%DB.DatasetMonthlyMetric{}, params)
  end

  defp changeset(:resource, %{datagouv_id: datagouv_id} = params) do
    params = Map.put(params, :resource_datagouv_id, datagouv_id)
    DB.ResourceMonthlyMetric.changeset(%DB.ResourceMonthlyMetric{}, params)
  end

  defp api_args(:dataset, datagouv_id: datagouv_id, page_size: page_size) do
    [dataset_id__exact: datagouv_id, page_size: page_size, metric_month__sort: "desc"] |> URI.encode_query()
  end

  defp api_args(:resource, datagouv_id: datagouv_id, page_size: page_size) do
    [resource_id__exact: datagouv_id, page_size: page_size, metric_month__sort: "desc"] |> URI.encode_query()
  end

  defp api_base_url(model_name) when model_name in [:dataset, :resource] do
    URI.new!("https://metric-api.data.gouv.fr/api/#{model_name}s/data/")
  end

  defp http_client, do: Transport.Req.impl()
end
