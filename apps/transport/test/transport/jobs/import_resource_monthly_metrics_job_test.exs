defmodule Transport.Test.Transport.Jobs.ImportResourceMonthlyMetricsTestJob do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportResourceMonthlyMetricsJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "import_metrics" do
    test "base case" do
      %DB.Resource{datagouv_id: datagouv_id} = insert(:resource)

      setup_http_response(datagouv_id, [
        %{
          "resource_id" => datagouv_id,
          "metric_month" => "2022-08",
          "monthly_download_resource" => 557_626
        },
        %{
          "resource_id" => datagouv_id,
          "metric_month" => "2022-07",
          "monthly_download_resource" => 343_617
        }
      ])

      assert DB.ResourceMonthlyMetric |> DB.Repo.all() |> Enum.empty?()

      Transport.Jobs.ImportMonthlyMetrics.import_metrics(:resource, datagouv_id)

      assert [
               %DB.ResourceMonthlyMetric{
                 resource_datagouv_id: ^datagouv_id,
                 year_month: "2022-08",
                 metric_name: :downloads,
                 count: 557_626
               },
               %DB.ResourceMonthlyMetric{
                 resource_datagouv_id: ^datagouv_id,
                 year_month: "2022-07",
                 metric_name: :downloads,
                 count: 343_617
               }
             ] = DB.Repo.all(DB.ResourceMonthlyMetric)
    end

    test "replaces existing records" do
      %DB.Resource{datagouv_id: datagouv_id} = insert(:resource)

      insert(:resource_monthly_metric,
        resource_datagouv_id: datagouv_id,
        year_month: "2023-12",
        metric_name: :downloads,
        count: 42
      )

      # This datagouv_id has already been imported, we should only fetch the
      # 3 latest records
      refute Transport.Jobs.ImportMonthlyMetrics.already_imported?(:resource, Ecto.UUID.generate())
      assert Transport.Jobs.ImportMonthlyMetrics.already_imported?(:resource, datagouv_id)

      setup_http_response(
        datagouv_id,
        [
          %{
            "resource_id" => datagouv_id,
            "metric_month" => "2023-12",
            "monthly_download_resource" => 43
          },
          %{
            "resource_id" => datagouv_id,
            "metric_month" => "2023-11",
            "monthly_download_resource" => 1337
          }
        ],
        page_size: 3
      )

      assert [
               %DB.ResourceMonthlyMetric{
                 id: metric_id,
                 resource_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :downloads,
                 count: 42
               }
             ] = DB.Repo.all(DB.ResourceMonthlyMetric)

      Transport.Jobs.ImportMonthlyMetrics.import_metrics(:resource, datagouv_id)

      assert [
               # Count has been updated, primary key is still the same
               %DB.ResourceMonthlyMetric{
                 id: ^metric_id,
                 resource_datagouv_id: ^datagouv_id,
                 year_month: "2023-12",
                 metric_name: :downloads,
                 count: 43,
                 inserted_at: inserted_at,
                 updated_at: updated_at
               },
               # Has been inserted
               %DB.ResourceMonthlyMetric{
                 resource_datagouv_id: ^datagouv_id,
                 year_month: "2023-11",
                 metric_name: :downloads,
                 count: 1337
               }
             ] = DB.Repo.all(DB.ResourceMonthlyMetric)

      # `updated_at` has been updated to reflect that this row has changed
      assert DateTime.after?(updated_at, inserted_at)
    end
  end

  test "perform" do
    %DB.Resource{datagouv_id: r1_datagouv_id} = insert(:resource)
    %DB.Resource{datagouv_id: r2_datagouv_id} = insert(:resource)

    assert MapSet.new([r1_datagouv_id, r2_datagouv_id]) ==
             ImportResourceMonthlyMetricsJob.resource_datagouv_ids() |> MapSet.new()

    setup_http_response(r1_datagouv_id, [
      %{
        "resource_id" => r1_datagouv_id,
        "metric_month" => "2023-12",
        "monthly_download_resource" => 43
      }
    ])

    setup_http_response(r2_datagouv_id, [
      %{
        "resource_id" => r2_datagouv_id,
        "metric_month" => "2023-12",
        "monthly_download_resource" => 5
      }
    ])

    assert :ok == perform_job(ImportResourceMonthlyMetricsJob, %{})

    assert 2 == DB.Repo.aggregate(DB.ResourceMonthlyMetric, :count, :id)

    assert [
             %DB.ResourceMonthlyMetric{
               resource_datagouv_id: ^r1_datagouv_id,
               year_month: "2023-12",
               metric_name: :downloads,
               count: 43
             }
           ] =
             DB.ResourceMonthlyMetric
             |> where([rmm], rmm.resource_datagouv_id == ^r1_datagouv_id)
             |> DB.Repo.all()

    assert [
             %DB.ResourceMonthlyMetric{
               resource_datagouv_id: ^r2_datagouv_id,
               year_month: "2023-12",
               metric_name: :downloads,
               count: 5
             }
           ] =
             DB.ResourceMonthlyMetric
             |> where([rmm], rmm.resource_datagouv_id == ^r2_datagouv_id)
             |> DB.Repo.all()
  end

  defp setup_http_response(datagouv_id, data, options \\ []) do
    page_size = Keyword.get(options, :page_size, 24)
    metrics_api_url = Transport.Jobs.ImportMonthlyMetrics.api_url(:resource, datagouv_id, page_size: page_size)

    expect(Transport.Req.Mock, :get, fn ^metrics_api_url, [] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}}
    end)
  end
end
