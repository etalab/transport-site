defmodule Transport.Jobs.ImportDatasetMonthlyMetricsJob do
  @moduledoc """
  Import monthly metrics related to datasets coming from the data.gouv.fr's API.

  This job is executed daily and imports metrics for all datasets for the last 2 years.
  Records are not supposed to change in the past, except for the current month.
  """
  use Oban.Worker, max_attempts: 3
  require Logger

  # Number of months to fetch for each dataset
  # 12*2 = 24 months
  @nb_records 12 * 2
  @api_base_url URI.new!("https://metric-api.data.gouv.fr/api/datasets/data/")

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
  end

  def import_metrics(dataset_datagouv_id) do
    url = api_url(dataset_datagouv_id)

    case http_client().get(url, []) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        body
        |> Jason.decode!()
        |> Map.fetch!("data")
        |> Enum.each(fn data -> insert_or_update(data, dataset_datagouv_id) end)

      other ->
        Logger.error(
          "metric-api.data.gouv.fr unexpected HTTP response for Dataset##{dataset_datagouv_id}: #{inspect(other)}"
        )
    end
  end

  @doc """
  iex> api_url("datagouv_id")
  "https://metric-api.data.gouv.fr/api/datasets/data/?dataset_id__exact=datagouv_id&page_size=24&metric_month__sort=desc"
  """
  def api_url(dataset_datagouv_id) do
    @api_base_url
    |> URI.append_query(
      URI.encode_query(dataset_id__exact: dataset_datagouv_id, page_size: @nb_records, metric_month__sort: "desc")
    )
    |> URI.to_string()
  end

  defp insert_or_update(
         %{
           "metric_month" => metric_month,
           "monthly_visit" => monthly_visit,
           "monthly_download_resource" => monthly_download_resource
         },
         dataset_datagouv_id
       ) do
    Enum.each([{:views, monthly_visit}, {:downloads, monthly_download_resource}], fn {metric_name, count} ->
      %DB.DatasetMonthlyMetric{}
      |> DB.DatasetMonthlyMetric.changeset(%{
        dataset_datagouv_id: dataset_datagouv_id,
        year_month: metric_month,
        metric_name: metric_name,
        count: count
      })
      |> DB.Repo.insert!(
        conflict_target: [:dataset_datagouv_id, :year_month, :metric_name],
        on_conflict: {:replace, [:count]}
      )
    end)
  end

  defp http_client, do: Transport.Req.impl()
end
