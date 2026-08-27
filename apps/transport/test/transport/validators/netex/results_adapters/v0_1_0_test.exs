defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_1_0Test do
  use ExUnit.Case, async: true
  doctest Transport.Validators.NeTEx.ResultsAdapters.V0_1_0, import: true
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_1_0
  import TransportWeb.PaginationHelpers, only: [make_pagination_config: 1]

  @xsd %{
    "code" => "xsd-123",
    "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
    "criticity" => "error"
  }
  @rule %{
    "code" => "valid-day-bits",
    "message" => "Mandatory attribute valid_day_bits not found",
    "criticity" => "error"
  }

  test "get_issues from binary, with errors" do
    pagination_config = make_pagination_config(%{})

    binary_result =
      result_factory("valid-day-bits": 41, "xsd-123": 41)
      |> V0_1_0.to_binary_result()

    assert {%{"issue_type" => "valid-day-bits"}, {41, repeated(@rule, 20)}} ==
             V0_1_0.get_issues(binary_result, %{}, pagination_config)

    assert {%{"issue_type" => "xsd-123"}, {41, repeated(@xsd, 20)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "xsd-123"}, pagination_config)

    assert {%{"issue_type" => "valid-day-bits"}, {41, repeated(@rule, 20)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "valid-day-bits"}, pagination_config)

    pagination_config = make_pagination_config(%{"page" => "3"})

    assert {%{"issue_type" => "valid-day-bits"}, {41, repeated(@rule, 1)}} ==
             V0_1_0.get_issues(binary_result, %{}, pagination_config)

    assert {%{"issue_type" => "xsd-123"}, {41, repeated(@xsd, 1)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "xsd-123"}, pagination_config)

    assert {%{"issue_type" => "valid-day-bits"}, {41, repeated(@rule, 1)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "valid-day-bits"}, pagination_config)
  end

  test "get_issues from binary, no error" do
    pagination_config = make_pagination_config(%{})

    binary_result =
      result_factory("xsd-123": 0, "valid-day-bits": 0)
      |> V0_1_0.to_binary_result()

    assert {%{"issue_type" => ""}, {0, repeated(@rule, 0)}} ==
             V0_1_0.get_issues(binary_result, %{}, pagination_config)

    assert {%{"issue_type" => "xsd-123"}, {0, repeated(@xsd, 0)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "xsd-123"}, pagination_config)

    assert {%{"issue_type" => "valid-day-bits"}, {0, repeated(@rule, 0)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "valid-day-bits"}, pagination_config)

    pagination_config = make_pagination_config(%{"page" => "3"})

    assert {%{"issue_type" => ""}, {0, repeated(@rule, 0)}} ==
             V0_1_0.get_issues(binary_result, %{}, pagination_config)

    assert {%{"issue_type" => "xsd-123"}, {0, repeated(@xsd, 0)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "xsd-123"}, pagination_config)

    assert {%{"issue_type" => "valid-day-bits"}, {0, repeated(@rule, 0)}} ==
             V0_1_0.get_issues(binary_result, %{"issue_type" => "valid-day-bits"}, pagination_config)
  end

  defp result_factory(counts) do
    counts
    |> Enum.flat_map(fn {category, count} ->
      error_factory(category, count)
    end)
  end

  defp error_factory(:"xsd-123", count), do: repeated(@xsd, count)
  defp error_factory(:"valid-day-bits", count), do: repeated(@rule, count)
  defp error_factory(_, _), do: []

  test "count_by_category_and_severity returns correct counts per category and severity" do
    # V0_1.0 synthesizes categories from code prefixes:
    # - "xsd-*" codes → "xsd-schema" category
    # - other codes → "base-rules" category
    xsd_errors = [
      %{
        "code" => "xsd-1",
        "criticity" => "error",
        "message" => "XSD Error A",
        "resource.filename" => "a.xml",
        "resource.line" => 10
      },
      %{
        "code" => "xsd-2",
        "criticity" => "warning",
        "message" => "XSD Warning A",
        "resource.filename" => "a.xml",
        "resource.line" => 20
      }
    ]

    base_errors = [
      %{
        "code" => "rule-a",
        "criticity" => "error",
        "message" => "Error A",
        "resource.filename" => "b.xml",
        "resource.line" => 5
      },
      %{
        "code" => "rule-b",
        "criticity" => "information",
        "message" => "Info A",
        "resource.filename" => "c.xml",
        "resource.line" => 30
      }
    ]

    # Build result map like the validator would produce
    result = %{
      "xsd-schema" => xsd_errors,
      "base-rules" => base_errors
    }

    binary_result = V0_1_0.to_binary_result(result)

    # Call count_by_category_and_severity with the parquet file path (binary)
    counts = V0_1_0.count_by_category_and_severity(binary_result)

    # Verify structure: %{"xsd-schema" => %{...}, "base-rules" => %{...}}
    assert Map.has_key?(counts, "xsd-schema")
    assert Map.has_key?(counts, "base-rules")

    xsd = counts["xsd-schema"]
    assert is_map(xsd)
    # 1 error, 1 warning in xsd-schema
    assert xsd["error"] == 1
    assert xsd["warning"] == 1

    base = counts["base-rules"]
    assert is_map(base)
    # 1 error, 1 information in base-rules
    assert base["error"] == 1
    assert base["information"] == 1
  end

  defp repeated(item, times) do
    [item]
    |> Stream.cycle()
    |> Enum.take(times)
  end
end
