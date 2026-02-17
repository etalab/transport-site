defmodule Transport.IRVE.DeduplicatorTest do
  use ExUnit.Case, async: true

  test "calculates duplicate statuses correctly" do
    test_df = create_test_dataframe()

    # IO.inspect(test_df)

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
               "deduplication_status" => "removed_because_resource_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-1",
               "deduplication_status" => "kept_because_date_maj_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-2",
               "deduplication_status" => "kept_because_resource_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-2",
               "deduplication_status" => "removed_because_date_maj_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-3",
               "deduplication_status" => "removed_because_resource_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             }
           ]

    # IO.inspect(result_df)
    # Explorer.DataFrame.print(result_df, limit: :infinity)
  end

  defp create_test_dataframe do
    # First resource - 3 entries, one unique PDC

    first_resource = %{
      "datagouv_dataset_id" => "dataset-1",
      "datagouv_resource_id" => "resource-1",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-15], ~T[10:30:00.000], "Etc/UTC")
    }

    first_resource_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31UNIQUE1",
          "date_maj" => ~D[2026-02-01]
        },
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE1",
          "date_maj" => ~D[2026-02-01]
        },
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE2",
          "date_maj" => ~D[2026-02-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, first_resource))

    # Second resource - 2 entries, duplicates of the first resource.
    # File is more recent but one of the date_maj is older.

    second_resource = %{
      "datagouv_dataset_id" => "dataset-2",
      "datagouv_resource_id" => "resource-2",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-17], ~T[14:15:00.000], "Etc/UTC")
    }

    second_resource_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE1",
          "date_maj" => ~D[2026-02-01]
        },
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE2",
          "date_maj" => ~D[2026-01-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, second_resource))

    # Third resource - 1 entry, same date_maj than first resource, but has an older datagouv_last_modified.
    # Should be removed.

    third_resource = %{
      "datagouv_dataset_id" => "dataset-3",
      "datagouv_resource_id" => "resource-3",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-02], ~T[09:00:00.000], "Etc/UTC")
    }

    third_resource_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE1",
          "date_maj" => ~D[2026-02-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, third_resource))

    data = first_resource_content ++ second_resource_content ++ third_resource_content

    Explorer.DataFrame.new(data)
  end
end
