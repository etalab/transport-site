defmodule Transport.IRVE.DeduplicatorTest do
  use ExUnit.Case, async: true

  test "calculates duplicate statuses correctly" do
    test_df = create_test_dataframe()

    result_df = Transport.IRVE.Deduplicator.add_duplicates_column(test_df)

    result_list =
      result_df
      |> Explorer.DataFrame.select(["id_pdc_itinerance", "datagouv_resource_id", "deduplication_status"])
      |> Explorer.DataFrame.to_rows()

    assert result_list == [
             %{
               "datagouv_resource_id" => "resource-1",
               "deduplication_status" => "unique",
               "id_pdc_itinerance" => "FRS31UNIQUE1"
             },
             %{
               "datagouv_resource_id" => "resource-1",
               "deduplication_status" => "removed_because_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-1",
               "deduplication_status" => "removed_because_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-2",
               "deduplication_status" => "kept_because_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-2",
               "deduplication_status" => "kept_because_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-3",
               "deduplication_status" => "removed_because_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             }
           ]

    # IO.inspect(result_df)
    # Explorer.DataFrame.print(result_df, limit: :infinity)
  end

  defp create_test_dataframe do
    data = [
      # First resource - 3 entries, one unique PDC
      %{
        "id_pdc_itinerance" => "FRS31UNIQUE1",
        "datagouv_dataset_id" => "dataset-1",
        "datagouv_resource_id" => "resource-1",
        "datagouv_last_modified" => DateTime.new!(~D[2026-02-01], ~T[10:30:00.000], "Etc/UTC")
      },
      %{
        "id_pdc_itinerance" => "FRS31DUPLICATE1",
        "datagouv_dataset_id" => "dataset-1",
        "datagouv_resource_id" => "resource-1",
        "datagouv_last_modified" => DateTime.new!(~D[2026-02-01], ~T[10:30:00.000], "Etc/UTC")
      },
      %{
        "id_pdc_itinerance" => "FRS31DUPLICATE2",
        "datagouv_dataset_id" => "dataset-1",
        "datagouv_resource_id" => "resource-1",
        "datagouv_last_modified" => DateTime.new!(~D[2026-02-01], ~T[10:30:00.000], "Etc/UTC")
      },
      # Second resource - 2 entries, duplicates of the first resource but more recent
      %{
        "id_pdc_itinerance" => "FRS31DUPLICATE1",
        "datagouv_dataset_id" => "dataset-2",
        "datagouv_resource_id" => "resource-2",
        "datagouv_last_modified" => DateTime.new!(~D[2026-02-02], ~T[14:15:00.000], "Etc/UTC")
      },
      %{
        "id_pdc_itinerance" => "FRS31DUPLICATE2",
        "datagouv_dataset_id" => "dataset-2",
        "datagouv_resource_id" => "resource-2",
        "datagouv_last_modified" => DateTime.new!(~D[2026-02-02], ~T[14:15:00.000], "Etc/UTC")
      },
      # Third resource - 1 entry, older duplicate
      %{
        "id_pdc_itinerance" => "FRS31DUPLICATE1",
        "datagouv_dataset_id" => "dataset-3",
        "datagouv_resource_id" => "resource-3",
        "datagouv_last_modified" => DateTime.new!(~D[2026-01-01], ~T[09:00:00.000], "Etc/UTC")
      }
    ]

    Explorer.DataFrame.new(data)
  end
end
