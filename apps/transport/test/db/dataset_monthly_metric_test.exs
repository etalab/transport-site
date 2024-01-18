defmodule DB.DatasetMonthlyMetricTest do
  use ExUnit.Case, async: true
  import DB.Factory

  doctest DB.DatasetMonthlyMetric, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "changeset" do
    test "can insert a record" do
      dataset = insert(:dataset)

      assert %Ecto.Changeset{valid?: true} =
               changeset =
               DB.DatasetMonthlyMetric.changeset(%DB.DatasetMonthlyMetric{}, %{
                 dataset_datagouv_id: dataset.datagouv_id,
                 metric_name: :views,
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
               DB.DatasetMonthlyMetric.changeset(%DB.DatasetMonthlyMetric{}, %{
                 dataset_datagouv_id: Ecto.UUID.generate(),
                 metric_name: :foo,
                 count: -1,
                 year_month: "bar"
               })
    end
  end

  test "downloads_for_year" do
    dataset = insert(:dataset)
    other_dataset = insert(:dataset)

    insert(:dataset_monthly_metric,
      dataset_datagouv_id: dataset.datagouv_id,
      year_month: "2023-12",
      metric_name: :downloads,
      count: 42
    )

    insert(:dataset_monthly_metric,
      dataset_datagouv_id: dataset.datagouv_id,
      year_month: "2023-01",
      metric_name: :downloads,
      count: 1_337
    )

    insert(:dataset_monthly_metric,
      dataset_datagouv_id: other_dataset.datagouv_id,
      year_month: "2023-10",
      metric_name: :downloads,
      count: 5
    )

    insert(:dataset_monthly_metric,
      dataset_datagouv_id: dataset.datagouv_id,
      year_month: "2023-12",
      metric_name: :views,
      count: 1
    )

    assert %{dataset.datagouv_id => 1_337 + 42} == DB.DatasetMonthlyMetric.downloads_for_year([dataset], 2023)

    assert %{dataset.datagouv_id => 1_337 + 42, other_dataset.datagouv_id => 5} ==
             DB.DatasetMonthlyMetric.downloads_for_year([dataset, other_dataset], 2023)

    assert %{} == DB.DatasetMonthlyMetric.downloads_for_year([dataset, other_dataset], 2024)
  end
end
