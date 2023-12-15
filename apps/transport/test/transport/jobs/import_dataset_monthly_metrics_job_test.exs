defmodule Transport.Test.Transport.Jobs.ImportDatasetMonthlyMetricsTestJob do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportDatasetMonthlyMetricsJob

  doctest ImportDatasetMonthlyMetricsJob, import: true

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "import_metrics" do
    test "base case" do
      %DB.Dataset{datagouv_id: datagouv_id} = insert(:dataset)

      metrics_api_url =
        "https://metric-api.data.gouv.fr/api/datasets/data/?dataset_id__exact=#{datagouv_id}&page_size=24&metric_month__sort=desc"

      Transport.Req.Mock
      |> expect(:get, fn ^metrics_api_url, [] ->
        data = [
          %{
            dataset_id: datagouv_id,
            metric_month: "2022-08",
            monthly_visit: 2633,
            monthly_download_resource: 557_626
          },
          %{
            dataset_id: datagouv_id,
            metric_month: "2022-07",
            monthly_visit: 1475,
            monthly_download_resource: 343_617
          }
        ]

        {:ok, %Req.Response{status: 200, body: Jason.encode!(%{"data" => data})}}
      end)

      assert DB.DatasetMonthlyMetric |> DB.Repo.all() |> Enum.empty?()

      ImportDatasetMonthlyMetricsJob.import_metrics(datagouv_id)

      assert [
               %DB.DatasetMonthlyMetric{
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2022-08",
                 metric_name: :views,
                 count: 2633
               },
               %DB.DatasetMonthlyMetric{
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2022-08",
                 metric_name: :downloads,
                 count: 557_626
               },
               %DB.DatasetMonthlyMetric{
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2022-07",
                 metric_name: :views,
                 count: 1475
               },
               %DB.DatasetMonthlyMetric{
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2022-07",
                 metric_name: :downloads,
                 count: 343_617
               }
             ] = DB.Repo.all(DB.DatasetMonthlyMetric)
    end

    test "replaces existing records" do
      %DB.Dataset{datagouv_id: datagouv_id} = insert(:dataset)

      insert(:dataset_monthly_metric,
        dataset_datagouv_id: datagouv_id,
        year_month: "2023-12",
        metric_name: :views,
        count: 42
      )

      metrics_api_url =
        "https://metric-api.data.gouv.fr/api/datasets/data/?dataset_id__exact=#{datagouv_id}&page_size=24&metric_month__sort=desc"

      Transport.Req.Mock
      |> expect(:get, fn ^metrics_api_url, [] ->
        data = [
          %{
            dataset_id: datagouv_id,
            metric_month: "2023-12",
            monthly_visit: 1337,
            monthly_download_resource: 43
          }
        ]

        {:ok, %Req.Response{status: 200, body: Jason.encode!(%{"data" => data})}}
      end)

      assert [
               %DB.DatasetMonthlyMetric{
                 id: metric_id,
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :views,
                 count: 42
               }
             ] = DB.Repo.all(DB.DatasetMonthlyMetric)

      ImportDatasetMonthlyMetricsJob.import_metrics(datagouv_id)

      assert [
               # Count has been updated, primary key is still the same
               %DB.DatasetMonthlyMetric{
                 id: ^metric_id,
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :views,
                 count: 1337
               },
               # Has been inserted
               %DB.DatasetMonthlyMetric{
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :downloads,
                 count: 43
               }
             ] = DB.Repo.all(DB.DatasetMonthlyMetric)
    end
  end
end
