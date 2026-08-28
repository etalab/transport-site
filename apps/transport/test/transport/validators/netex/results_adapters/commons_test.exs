defmodule Transport.Validators.NeTEx.ResultsAdapters.CommonsTest do
  use ExUnit.Case, async: true
  alias Transport.Validators.NeTEx.ResultsAdapters.Commons
  require Explorer.DataFrame, as: DF
  import TransportWeb.PaginationHelpers, only: [make_pagination_config: 1, make_pagination_config: 2]

  doctest Transport.Validators.NeTEx.ResultsAdapters.Commons, import: true

  @xsd %{
    "code" => "xsd-123",
    "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
    "criticity" => "error",
    "resource" => %{
      "line" => 1,
      "filename" => "stops.xml"
    }
  }

  @rule %{
    "code" => "valid-day-bits",
    "message" => "Mandatory attribute valid_day_bits not found",
    "criticity" => "error"
  }

  @errors [@xsd, @rule]

  test "dataframe building" do
    assert [
             %{
               "code" => "xsd-123",
               "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
               "criticity" => "error",
               "category" => nil,
               "resource.class" => nil,
               "resource.column" => nil,
               "resource.filename" => "stops.xml",
               "resource.id" => nil,
               "resource.line" => 1
             },
             %{
               "code" => "valid-day-bits",
               "message" => "Mandatory attribute valid_day_bits not found",
               "criticity" => "error",
               "category" => nil,
               "resource.class" => nil,
               "resource.column" => nil,
               "resource.filename" => nil,
               "resource.id" => nil,
               "resource.line" => nil
             }
           ] == example() |> DF.to_rows()
  end

  test "count_and_slice handles empty dataframe (no rows)" do
    # Create an empty dataframe by filtering to a category that doesn't exist
    errors = [
      %{
        "code" => "xsd-1",
        "criticity" => "error",
        "message" => "Error A",
        "resource.filename" => "a.xml",
        "resource.line" => 1
      }
    ]

    df =
      errors
      |> Commons.to_dataframe(fn _ -> %{} end)
      |> DF.filter(category == "nonexistent-category")

    # Filtered dataframe has columns but zero rows
    assert Explorer.DataFrame.names(df) != []
    assert Explorer.Series.count(df["code"]) == 0

    pagination_config = make_pagination_config(%{})
    assert {0, []} == Commons.count_and_slice(df, pagination_config)
  end

  test "count_and_slice works normally with data" do
    errors = [
      %{
        "code" => "xsd-1",
        "criticity" => "error",
        "message" => "Error A",
        "resource.filename" => "a.xml",
        "resource.line" => 1
      },
      %{
        "code" => "xsd-2",
        "criticity" => "warning",
        "message" => "Warning B",
        "resource.filename" => "b.xml",
        "resource.line" => 2
      }
    ]

    df =
      errors
      |> Commons.to_dataframe(fn _ -> %{} end)

    pagination_config = make_pagination_config(%{})
    {total, issues} = Commons.count_and_slice(df, pagination_config)
    assert total == 2
    assert length(issues) == 2
  end

  test "serialisation roundtrip" do
    df = example()
    assert df |> DF.to_rows() == df |> Commons.to_binary() |> Commons.from_binary() |> DF.to_rows()
  end

  def example do
    Commons.to_dataframe(@errors, fn _ -> %{} end)
  end

  describe "summary_from_binary/2" do
    test "returns per-category stats with worst criticity and count" do
      errors = [
        %{"code" => "xsd-1", "criticity" => "error", "category" => "xsd-schema"},
        %{"code" => "xsd-2", "criticity" => "error", "category" => "xsd-schema"},
        %{"code" => "rule-1", "criticity" => "warning", "category" => "base-rules"},
        %{"code" => "rule-2", "criticity" => "information", "category" => "base-rules"}
      ]

      df = Commons.to_dataframe(errors, fn _ -> %{} end)
      binary = Commons.to_binary(df)

      result = Commons.summary_from_binary(binary, ["xsd-schema", "base-rules"])

      assert length(result) == 2

      xsd = Enum.find(result, &(&1["category"] == "xsd-schema"))
      assert xsd["stats"] == %{"count" => 2, "criticity" => "error"}

      base = Enum.find(result, &(&1["category"] == "base-rules"))
      assert base["stats"] == %{"count" => 1, "criticity" => "warning"}
    end

    test "returns all categories with count 0 and NoError when empty" do
      df = Commons.to_dataframe([], fn _ -> %{} end)
      binary = Commons.to_binary(df)

      result = Commons.summary_from_binary(binary, ["xsd-schema", "base-rules"])

      assert length(result) == 2
      xsd = Enum.find(result, &(&1["category"] == "xsd-schema"))
      assert xsd["stats"] == %{"count" => 0, "criticity" => "NoError"}
    end
  end

  describe "count_and_slice/2" do
    test "sorts by criticity severity (error > warning > information), not lexicographically" do
      # Lexicographic order would give: error < information < warning
      # Severity order should be: error > warning > information
      pagination_config = make_pagination_config(%{"page_size" => "10"})

      errors = [
        %{
          "code" => "rule-a",
          "criticity" => "information",
          "message" => "Info A",
          "resource.filename" => "b.xml",
          "resource.line" => 10
        },
        %{
          "code" => "rule-b",
          "criticity" => "warning",
          "message" => "Warning B",
          "resource.filename" => "a.xml",
          "resource.line" => 5
        },
        %{
          "code" => "rule-c",
          "criticity" => "error",
          "message" => "Error C",
          "resource.filename" => "c.xml",
          "resource.line" => 1
        }
      ]

      df = errors |> Commons.to_dataframe(fn _ -> %{} end)

      assert {3, issues} = Commons.count_and_slice(df, pagination_config)

      criticity_order = Enum.map(issues, & &1["criticity"])
      assert criticity_order == ["error", "warning", "information"]
    end

    test "sorts by message as tiebreaker when severity, filename and line are equal" do
      pagination_config = make_pagination_config(%{"page_size" => "10"})

      errors = [
        %{
          "code" => "rule-3",
          "criticity" => "error",
          "message" => "Third message",
          "resource.filename" => "a.xml",
          "resource.line" => 1
        },
        %{
          "code" => "rule-1",
          "criticity" => "error",
          "message" => "Alpha message",
          "resource.filename" => "a.xml",
          "resource.line" => 1
        },
        %{
          "code" => "rule-2",
          "criticity" => "error",
          "message" => "Middle message",
          "resource.filename" => "a.xml",
          "resource.line" => 1
        }
      ]

      df = errors |> Commons.to_dataframe(fn _ -> %{} end)

      assert {3, issues} = Commons.count_and_slice(df, pagination_config)

      message_order = Enum.map(issues, & &1["message"])
      assert message_order == ["Alpha message", "Middle message", "Third message"]
    end

    test "pagination returns the correct page after sorting" do
      # 5 errors total, page_size=2 → page 2 should return items 3-4 (0-indexed: 2-3)
      pagination_config = make_pagination_config(%{"page" => "2"}, 2)

      errors = [
        %{
          "code" => "r1",
          "criticity" => "error",
          "message" => "E1",
          "resource.filename" => "a.xml",
          "resource.line" => 1
        },
        %{
          "code" => "r2",
          "criticity" => "warning",
          "message" => "W1",
          "resource.filename" => "a.xml",
          "resource.line" => 1
        },
        %{
          "code" => "r3",
          "criticity" => "error",
          "message" => "E2",
          "resource.filename" => "b.xml",
          "resource.line" => 1
        },
        %{
          "code" => "r4",
          "criticity" => "information",
          "message" => "I1",
          "resource.filename" => "a.xml",
          "resource.line" => 1
        },
        %{
          "code" => "r5",
          "criticity" => "error",
          "message" => "E3",
          "resource.filename" => "c.xml",
          "resource.line" => 1
        }
      ]

      df = errors |> Commons.to_dataframe(fn _ -> %{} end)

      assert {5, issues} = Commons.count_and_slice(df, pagination_config)
      assert length(issues) == 2

      # Sorted order: error(a.xml/E1), error(b.xml/E2), error(c.xml/E3), warning(W1), information(I1)
      # Page 2 (1-indexed) = items at index 2-3 = E3, W1
      codes = Enum.map(issues, & &1["code"])
      criticities = Enum.map(issues, & &1["criticity"])
      assert codes == ["r5", "r2"]
      assert criticities == ["error", "warning"]
    end
  end

  describe "count_by_category_and_severity/1" do
    test "returns per-category, per-severity counts" do
      errors = [
        %{"code" => "xsd-1", "criticity" => "error", "category" => "xsd-schema"},
        %{"code" => "xsd-2", "criticity" => "warning", "category" => "xsd-schema"},
        %{"code" => "rule-1", "criticity" => "error", "category" => "base-rules"},
        %{"code" => "rule-2", "criticity" => "information", "category" => "base-rules"}
      ]

      df = Commons.to_dataframe(errors, fn _ -> %{} end)
      binary = Commons.to_binary(df)

      result = Commons.count_by_category_and_severity(binary)

      assert result == %{
               "xsd-schema" => %{"error" => 1, "warning" => 1},
               "base-rules" => %{"error" => 1, "information" => 1}
             }
    end

    test "returns empty map when no rows" do
      df = Commons.to_dataframe([], fn _ -> %{} end)
      binary = Commons.to_binary(df)

      assert Commons.count_by_category_and_severity(binary) == %{}
    end
  end
end
