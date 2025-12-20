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
  end
end
