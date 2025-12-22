defmodule DB.ResourceMonthlyMetricTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "changeset" do
    test "can insert a record" do
      resource = insert(:resource)

      assert %Ecto.Changeset{valid?: true} =
               changeset =
               DB.ResourceMonthlyMetric.changeset(%DB.ResourceMonthlyMetric{}, %{
                 resource_datagouv_id: resource.datagouv_id,
                 metric_name: :downloads,
                 count: 42,
                 year_month: "2023-12"
               })

      DB.Repo.insert!(changeset)
    end

    test "identifies errors" do
      assert %Ecto.Changeset{
               valid?: false,
               errors: [
                 {:count, _},
                 {:year_month, _},
                 {:metric_name, _}
               ]
             } =
               DB.ResourceMonthlyMetric.changeset(%DB.ResourceMonthlyMetric{}, %{
                 resource_datagouv_id: Ecto.UUID.generate(),
                 metric_name: :foo,
                 count: -1,
                 year_month: "bar"
               })
    end

    test "downloads_for_year" do
      resource = insert(:resource)
      other_resource = insert(:resource)

      insert(:resource_monthly_metric,
        resource_datagouv_id: resource.datagouv_id,
        year_month: "2023-12",
        metric_name: :downloads,
        count: 42
      )

      insert(:resource_monthly_metric,
        resource_datagouv_id: resource.datagouv_id,
        year_month: "2023-01",
        metric_name: :downloads,
        count: 1_337
      )

      insert(:resource_monthly_metric,
        resource_datagouv_id: other_resource.datagouv_id,
        year_month: "2023-10",
        metric_name: :downloads,
        count: 5
      )

      assert %{resource.datagouv_id => 1_337 + 42} == DB.ResourceMonthlyMetric.downloads_for_year([resource], 2023)

      assert %{resource.datagouv_id => 1_337 + 42, other_resource.datagouv_id => 5} ==
               DB.ResourceMonthlyMetric.downloads_for_year([resource, other_resource], 2023)

      assert %{} == DB.ResourceMonthlyMetric.downloads_for_year([resource, other_resource], 2024)
    end
    
    test "download_statistics" do
      dataset = insert(:dataset, custom_title: "Title")

      resource =
        insert(:resource,
          title: "GTFS",
          url: "https://static.data.gouv.fr/url",
          dataset: dataset,
          datagouv_id: "a" <> Ecto.UUID.generate()
        )

      assert resource |> DB.Resource.hosted_on_datagouv?()

      other_resource =
        insert(:resource,
          title: "GTFS 2",
          url: "https://static.data.gouv.fr/url2",
          dataset: dataset,
          datagouv_id: "b" <> Ecto.UUID.generate()
        )

      assert other_resource |> DB.Resource.hosted_on_datagouv?()

      insert(:resource_monthly_metric,
        metric_name: :downloads,
        dataset_datagouv_id: dataset.datagouv_id,
        resource_datagouv_id: resource.datagouv_id,
        count: 2,
        year_month: "2025-12"
      )

      insert(:resource_monthly_metric,
        metric_name: :downloads,
        dataset_datagouv_id: dataset.datagouv_id,
        resource_datagouv_id: resource.datagouv_id,
        count: 3,
        year_month: "2025-11"
      )

      insert(:resource_monthly_metric,
        metric_name: :downloads,
        dataset_datagouv_id: dataset.datagouv_id,
        resource_datagouv_id: other_resource.datagouv_id,
        count: 4,
        year_month: "2025-11"
      )

      assert [dataset |> DB.Repo.preload(:resources)] |> DB.ResourceMonthlyMetric.download_statistics() == [
               %{
                 count: 3,
                 dataset_title: "Title",
                 resource_title: "GTFS",
                 year_month: "2025-11",
                 resource_datagouv_id: resource.datagouv_id,
                 dataset_datagouv_id: dataset.datagouv_id
               },
               %{
                 count: 4,
                 dataset_title: "Title",
                 resource_title: "GTFS 2",
                 year_month: "2025-11",
                 resource_datagouv_id: other_resource.datagouv_id,
                 dataset_datagouv_id: dataset.datagouv_id
               },
               %{
                 count: 2,
                 dataset_title: "Title",
                 resource_title: "GTFS",
                 year_month: "2025-12",
                 resource_datagouv_id: resource.datagouv_id,
                 dataset_datagouv_id: dataset.datagouv_id
               }
             ]
    end
  end
end
