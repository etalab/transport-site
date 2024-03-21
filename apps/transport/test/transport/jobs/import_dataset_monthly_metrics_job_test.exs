defmodule Transport.Test.Transport.Jobs.ImportDatasetMonthlyMetricsJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportDatasetMonthlyMetricsJob

  doctest Transport.Jobs.ImportMonthlyMetrics, import: true

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "import_metrics" do
    test "base case" do
      %DB.Dataset{datagouv_id: datagouv_id} = insert(:dataset)

      setup_http_response(datagouv_id, [
        %{
          "dataset_id" => datagouv_id,
          "metric_month" => "2022-08",
          "monthly_visit" => 2633,
          "monthly_download_resource" => 557_626
        },
        %{
          "dataset_id" => datagouv_id,
          "metric_month" => "2022-07",
          "monthly_visit" => 1475,
          "monthly_download_resource" => 343_617
        }
      ])

      assert DB.DatasetMonthlyMetric |> DB.Repo.all() |> Enum.empty?()

      Transport.Jobs.ImportMonthlyMetrics.import_metrics(:dataset, datagouv_id)

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

      # This datagouv_id has already been imported, we should only fetch the
      # 3 latest records
      refute Transport.Jobs.ImportMonthlyMetrics.already_imported?(:dataset, Ecto.UUID.generate())
      assert Transport.Jobs.ImportMonthlyMetrics.already_imported?(:dataset, datagouv_id)

      setup_http_response(
        datagouv_id,
        [
          %{
            "dataset_id" => datagouv_id,
            "metric_month" => "2023-12",
            "monthly_visit" => 1337,
            "monthly_download_resource" => 43
          }
        ],
        page_size: 3
      )

      assert [
               %DB.DatasetMonthlyMetric{
                 id: metric_id,
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :views,
                 count: 42
               }
             ] = DB.Repo.all(DB.DatasetMonthlyMetric)

      Transport.Jobs.ImportMonthlyMetrics.import_metrics(:dataset, datagouv_id)

      assert [
               # Count has been updated, primary key is still the same
               %DB.DatasetMonthlyMetric{
                 id: ^metric_id,
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :views,
                 count: 1337,
                 inserted_at: inserted_at,
                 updated_at: updated_at
               },
               # Has been inserted
               %DB.DatasetMonthlyMetric{
                 dataset_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :downloads,
                 count: 43
               }
             ] = DB.Repo.all(DB.DatasetMonthlyMetric)

      # `updated_at` has been updated to reflect that this row has changed
      assert DateTime.after?(updated_at, inserted_at)
    end
  end

  test "perform" do
    %DB.Dataset{datagouv_id: d1_datagouv_id} = insert(:dataset)
    %DB.Dataset{datagouv_id: d2_datagouv_id} = insert(:dataset)
    insert(:dataset, is_active: false)
    insert(:dataset, is_active: true, is_hidden: true)

    assert MapSet.new([d1_datagouv_id, d2_datagouv_id]) ==
             ImportDatasetMonthlyMetricsJob.dataset_datagouv_ids() |> MapSet.new()

    setup_http_responses([
      {d1_datagouv_id,
       [
         %{
           "dataset_id" => d1_datagouv_id,
           "metric_month" => "2023-12",
           "monthly_visit" => 1337,
           "monthly_download_resource" => 43
         }
       ]},
      {d2_datagouv_id,
       [
         %{
           "dataset_id" => d2_datagouv_id,
           "metric_month" => "2023-12",
           "monthly_visit" => nil,
           "monthly_download_resource" => 5
         }
       ]}
    ])

    assert :ok == perform_job(ImportDatasetMonthlyMetricsJob, %{})

    assert 4 == DB.Repo.aggregate(DB.DatasetMonthlyMetric, :count, :id)

    assert [
             %DB.DatasetMonthlyMetric{
               dataset_datagouv_id: ^d1_datagouv_id,
               year_month: "2023-12",
               metric_name: :downloads,
               count: 43
             },
             %DB.DatasetMonthlyMetric{
               dataset_datagouv_id: ^d1_datagouv_id,
               year_month: "2023-12",
               metric_name: :views,
               count: 1337
             }
           ] =
             DB.DatasetMonthlyMetric
             |> where([dmm], dmm.dataset_datagouv_id == ^d1_datagouv_id)
             |> order_by([dmm], dmm.metric_name)
             |> DB.Repo.all()

    assert [
             %DB.DatasetMonthlyMetric{
               dataset_datagouv_id: ^d2_datagouv_id,
               year_month: "2023-12",
               metric_name: :downloads,
               count: 5
             },
             %DB.DatasetMonthlyMetric{
               dataset_datagouv_id: ^d2_datagouv_id,
               year_month: "2023-12",
               metric_name: :views,
               count: 0
             }
           ] =
             DB.DatasetMonthlyMetric
             |> where([dmm], dmm.dataset_datagouv_id == ^d2_datagouv_id)
             |> order_by([dmm], dmm.metric_name)
             |> DB.Repo.all()
  end

  defp setup_http_responses(data) when is_list(data) do
    responses =
      Enum.into(data, %{}, fn {datagouv_id, response} ->
        {Transport.Jobs.ImportMonthlyMetrics.api_url(:dataset, datagouv_id, page_size: 24), response}
      end)

    # HTTP requests order is not important
    expect(Transport.Req.Mock, :get, Enum.count(responses), fn url, [] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => Map.fetch!(responses, url)}}}
    end)
  end

  defp setup_http_response(datagouv_id, data, options \\ []) do
    page_size = Keyword.get(options, :page_size, 24)
    metrics_api_url = Transport.Jobs.ImportMonthlyMetrics.api_url(:dataset, datagouv_id, page_size: page_size)

    expect(Transport.Req.Mock, :get, fn ^metrics_api_url, [] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}}
    end)
  end
end
