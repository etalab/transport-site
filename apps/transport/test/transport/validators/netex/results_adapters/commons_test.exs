defmodule Transport.Validators.NeTEx.ResultsAdapters.CommonsTest do
  use ExUnit.Case, async: true
  alias Transport.Validators.NeTEx.ResultsAdapters.Commons
  require Explorer.DataFrame, as: DF
  import TransportWeb.PaginationHelpers, only: [make_pagination_config: 1, make_pagination_config: 2]

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
               "resource.class" => nil,
               "resource.column" => nil,
               "resource.filename" => nil,
               "resource.id" => nil,
               "resource.line" => nil
             }
           ] == example() |> DF.to_rows()
  end

  test "serialisation roundtrip" do
    df = example()
    assert df |> DF.to_rows() == df |> Commons.to_binary() |> Commons.from_binary() |> DF.to_rows()
  end

  def example do
    Commons.to_dataframe(@errors, fn _ -> %{} end)
  end

  describe "count_and_slice/2" do
    test "sorts by criticity severity (error > warning > information), not lexicographically" do
      # Severity order: error(1) > warning(2) > information(3)
      # Input is interleaved to ensure the sort actually reorders them
      pagination_config = make_pagination_config(%{"page_size" => "10"})

      errors = [
        %{
          "code" => "rule-a",
          "criticity" => "information",
          "message" => "Info A",
          "resource" => %{"filename" => "b.xml", "line" => 10},
          "class" => nil
        },
        %{
          "code" => "rule-b",
          "criticity" => "warning",
          "message" => "Warning B",
          "resource" => %{"filename" => "a.xml", "line" => 5},
          "class" => nil
        },
        %{
          "code" => "rule-c",
          "criticity" => "error",
          "message" => "Error C",
          "resource" => %{"filename" => "c.xml", "line" => 1},
          "class" => nil
        }
      ]

      df = errors |> Commons.to_dataframe(fn _ -> %{} end)

      assert {3, issues} = Commons.count_and_slice(df, pagination_config)

      criticity_order = Enum.map(issues, & &1["criticity"])
      assert criticity_order == ["error", "warning", "information"]
    end

    test "sorts filenames alphabetically, not by insertion order" do
      # All same severity → tiebreaker is filename. Must sort alphabetically,
      # not by the category column's internal code (insertion) order.
      pagination_config = make_pagination_config(%{"page_size" => "10"})

      errors = [
        %{
          "code" => "r0",
          "criticity" => "error",
          "message" => "m",
          "resource" => %{"filename" => "zebra.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "r1",
          "criticity" => "error",
          "message" => "m",
          "resource" => %{"filename" => "alpha.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "r2",
          "criticity" => "error",
          "message" => "m",
          "resource" => %{"filename" => "mid.xml", "line" => 1},
          "class" => nil
        }
      ]

      df = errors |> Commons.to_dataframe(fn _ -> %{} end)

      assert {3, issues} = Commons.count_and_slice(df, pagination_config)

      filenames = Enum.map(issues, & &1["resource"]["filename"])
      assert filenames == ["alpha.xml", "mid.xml", "zebra.xml"]
    end

    test "sorts by line number as secondary tiebreaker after filename" do
      # Same severity + same filename → sort by line number ascending
      pagination_config = make_pagination_config(%{"page_size" => "10"})

      errors = [
        %{
          "code" => "r3",
          "criticity" => "error",
          "message" => "Line 3",
          "resource" => %{"filename" => "a.xml", "line" => 30},
          "class" => nil
        },
        %{
          "code" => "r1",
          "criticity" => "error",
          "message" => "Line 1",
          "resource" => %{"filename" => "a.xml", "line" => 10},
          "class" => nil
        },
        %{
          "code" => "r2",
          "criticity" => "error",
          "message" => "Line 2",
          "resource" => %{"filename" => "a.xml", "line" => 20},
          "class" => nil
        }
      ]

      df = errors |> Commons.to_dataframe(fn _ -> %{} end)

      assert {3, issues} = Commons.count_and_slice(df, pagination_config)

      lines = Enum.map(issues, & &1["resource"]["line"])
      assert lines == [10, 20, 30]
    end

    test "sorts by message as final tiebreaker when severity, filename and line are equal" do
      pagination_config = make_pagination_config(%{"page_size" => "10"})

      errors = [
        %{
          "code" => "rule-3",
          "criticity" => "error",
          "message" => "Third message",
          "resource" => %{"filename" => "a.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "rule-1",
          "criticity" => "error",
          "message" => "Alpha message",
          "resource" => %{"filename" => "a.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "rule-2",
          "criticity" => "error",
          "message" => "Middle message",
          "resource" => %{"filename" => "a.xml", "line" => 1},
          "class" => nil
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
          "resource" => %{"filename" => "a.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "r2",
          "criticity" => "warning",
          "message" => "W1",
          "resource" => %{"filename" => "a.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "r3",
          "criticity" => "error",
          "message" => "E2",
          "resource" => %{"filename" => "b.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "r4",
          "criticity" => "information",
          "message" => "I1",
          "resource" => %{"filename" => "a.xml", "line" => 1},
          "class" => nil
        },
        %{
          "code" => "r5",
          "criticity" => "error",
          "message" => "E3",
          "resource" => %{"filename" => "c.xml", "line" => 1},
          "class" => nil
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
end
