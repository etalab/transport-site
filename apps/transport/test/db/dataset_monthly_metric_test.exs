defmodule DB.DatasetMonthlyMetricTest do
  use ExUnit.Case, async: true
  import DB.Factory

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
end
