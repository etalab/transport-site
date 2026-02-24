defmodule Transport.IRVE.DeduplicatorTest do
  use ExUnit.Case, async: true

  test "calculates duplicate statuses correctly" do
    test_df = create_test_dataframe()

    result_df = Transport.IRVE.Deduplicator.add_duplicates_column(test_df)

    result_list =
      result_df
      |> Explorer.DataFrame.select(["id_pdc_itinerance", "datagouv_resource_id", "date_maj", "deduplication_status"])
      |> Explorer.DataFrame.to_rows()

    assert result_list == [
             %{
               "datagouv_resource_id" => "resource-2026-02-15",
               "date_maj" => ~D[2026-02-01],
               "deduplication_status" => "unique",
               "id_pdc_itinerance" => "FRS31UNIQUE1"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-15",
               "date_maj" => ~D[2026-02-01],
               "deduplication_status" => "removed_because_resource_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-15",
               "date_maj" => ~D[2026-02-01],
               "deduplication_status" => "kept_because_date_maj_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-15",
               "date_maj" => ~D[2026-02-02],
               "deduplication_status" => "removed_because_not_in_prioritary_dataset",
               "id_pdc_itinerance" => "FRS31DUPLICATE3"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-17",
               "date_maj" => ~D[2026-02-01],
               "deduplication_status" => "kept_because_resource_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-17",
               "date_maj" => ~D[2026-01-01],
               "deduplication_status" => "removed_because_date_maj_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-01",
               "date_maj" => ~D[2026-02-01],
               "deduplication_status" => "removed_because_resource_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-18",
               "date_maj" => ~D[2025-12-01],
               "deduplication_status" => "removed_because_date_maj_not_more_recent",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "gireve-resource",
               "date_maj" => ~D[2025-10-01],
               "deduplication_status" => "kept_because_in_prioritary_dataset",
               "id_pdc_itinerance" => "FRS31DUPLICATE3"
             },
             %{
               "datagouv_resource_id" => "qualicharge-resource",
               "date_maj" => ~D[2025-10-01],
               "deduplication_status" => "removed_because_not_in_prioritary_dataset",
               "id_pdc_itinerance" => "FRS31DUPLICATE3"
             },
             %{
               "datagouv_resource_id" => "non-itinerance-resource",
               "date_maj" => ~D[2025-10-01],
               "deduplication_status" => "removed_because_non_concerne",
               "id_pdc_itinerance" => "Non concerné"
             },
             %{
               "datagouv_resource_id" => "with-exact-duplicates-resource",
               "date_maj" => ~D[2025-10-01],
               "deduplication_status" => "kept_because_exact_duplicate_in_same_file",
               "id_pdc_itinerance" => "FRS31DUPLICATE5"
             },
             %{
               "datagouv_resource_id" => "with-exact-duplicates-resource",
               "date_maj" => ~D[2025-10-01],
               "deduplication_status" => "removed_because_exact_duplicate_in_same_file",
               "id_pdc_itinerance" => "FRS31DUPLICATE5"
             }
           ]
  end

  test "we can generate a deduplicated dataframe" do
    test_df = create_test_dataframe()

    result_df =
      test_df
      |> Transport.IRVE.Deduplicator.add_duplicates_column()
      |> Transport.IRVE.Deduplicator.discard_duplicates()

    result_list =
      result_df
      |> Explorer.DataFrame.select(["id_pdc_itinerance", "datagouv_resource_id"])
      |> Explorer.DataFrame.to_rows()

    assert result_list == [
             %{
               "datagouv_resource_id" => "resource-2026-02-15",
               "id_pdc_itinerance" => "FRS31UNIQUE1"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-15",
               "id_pdc_itinerance" => "FRS31DUPLICATE2"
             },
             %{
               "datagouv_resource_id" => "resource-2026-02-17",
               "id_pdc_itinerance" => "FRS31DUPLICATE1"
             },
             %{
               "datagouv_resource_id" => "gireve-resource",
               "id_pdc_itinerance" => "FRS31DUPLICATE3"
             },
             %{
               "datagouv_resource_id" => "with-exact-duplicates-resource",
               "id_pdc_itinerance" => "FRS31DUPLICATE5"
             }
           ]
  end

  defp create_test_dataframe do
    # First resource - 3 entries, one unique PDC

    resource_2026_02_15 = %{
      "datagouv_dataset_id" => "dataset-2026-02-15",
      "datagouv_resource_id" => "resource-2026-02-15",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-15], ~T[10:30:00.000], "Etc/UTC")
    }

    resource_2026_02_15_content =
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
        },
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE3",
          "date_maj" => ~D[2026-02-02]
        }
      ]
      |> Enum.map(&Map.merge(&1, resource_2026_02_15))

    # Second resource - 2 entries, duplicates of the first resource.
    # File is more recent but one of the date_maj is older.

    resource_2026_02_17 = %{
      "datagouv_dataset_id" => "dataset-2026-02-17",
      "datagouv_resource_id" => "resource-2026-02-17",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-17], ~T[14:15:00.000], "Etc/UTC")
    }

    resource_2026_02_17_content =
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
      |> Enum.map(&Map.merge(&1, resource_2026_02_17))

    # Third resource - 1 entry, same date_maj than first resource, but has an older datagouv_last_modified.
    # Should be removed.

    resource_2026_02_01 = %{
      "datagouv_dataset_id" => "dataset-2026-02-01",
      "datagouv_resource_id" => "resource-2026-02-01",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-02], ~T[09:00:00.000], "Etc/UTC")
    }

    resource_2026_02_01_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE1",
          "date_maj" => ~D[2026-02-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, resource_2026_02_01))

    # Tricky case! Has been published the most recently, but the date_maj is older. Should be removed.
    reource_2026_02_18 = %{
      "datagouv_dataset_id" => "dataset-2026-02-18",
      "datagouv_resource_id" => "resource-2026-02-18",
      "datagouv_last_modified" => DateTime.new!(~D[2026-02-18], ~T[10:00:00.000], "Etc/UTC")
    }

    reource_2026_02_18_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE1",
          "date_maj" => ~D[2025-12-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, reource_2026_02_18))

    # Last resources for testing the prioritary list filter. Both are quite old but they should take the lead.

    gireve_resource = %{
      "datagouv_dataset_id" => "63dccb1307e9b2f213a5130c",
      "datagouv_resource_id" => "gireve-resource",
      "datagouv_last_modified" => DateTime.new!(~D[2025-11-01], ~T[12:00:00.000], "Etc/UTC")
    }

    gireve_resource_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE3",
          "date_maj" => ~D[2025-10-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, gireve_resource))

    qualicharge_resource = %{
      "datagouv_dataset_id" => "6818bce2d9af175f6e01a1b2",
      "datagouv_resource_id" => "qualicharge-resource",
      "datagouv_last_modified" => DateTime.new!(~D[2025-11-01], ~T[12:00:00.000], "Etc/UTC")
    }

    qualicharge_resource_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE3",
          "date_maj" => ~D[2025-10-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, qualicharge_resource))

    non_itinerance_resource = %{
      "datagouv_dataset_id" => "non-itinerance-dataset",
      "datagouv_resource_id" => "non-itinerance-resource",
      "datagouv_last_modified" => DateTime.new!(~D[2025-11-01], ~T[12:00:00.000], "Etc/UTC")
    }

    non_itinerance_resource_content =
      [
        %{
          "id_pdc_itinerance" => "Non concerné",
          "date_maj" => ~D[2025-10-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, non_itinerance_resource))

    resource_with_exact_duplicates = %{
      "datagouv_dataset_id" => "with-exact-duplicates-dataset",
      "datagouv_resource_id" => "with-exact-duplicates-resource",
      "datagouv_last_modified" => DateTime.new!(~D[2025-11-01], ~T[12:00:00.000], "Etc/UTC")
    }

    resource_with_exact_duplicates_content =
      [
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE5",
          "date_maj" => ~D[2025-10-01]
        },
        %{
          "id_pdc_itinerance" => "FRS31DUPLICATE5",
          "date_maj" => ~D[2025-10-01]
        }
      ]
      |> Enum.map(&Map.merge(&1, resource_with_exact_duplicates))

    data =
      resource_2026_02_15_content ++
        resource_2026_02_17_content ++
        resource_2026_02_01_content ++
        reource_2026_02_18_content ++
        gireve_resource_content ++
        qualicharge_resource_content ++
        non_itinerance_resource_content ++
        resource_with_exact_duplicates_content

    Explorer.DataFrame.new(data)
  end
end
