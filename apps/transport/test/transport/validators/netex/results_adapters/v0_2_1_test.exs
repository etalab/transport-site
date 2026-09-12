defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_1Test do
  use ExUnit.Case, async: true
  doctest Transport.Validators.NeTEx.ResultsAdapters.V0_2_1, import: true
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_1
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_2
  import Transport.Test.Validators.NeTEx.SummaryFromBinary
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

    for module <- [V0_2_1, V0_2_2] do
      binary_result =
        result_factory("base-rules": 41, "xsd-schema": 41)
        |> module.to_binary_result()

      assert {%{"issues_category" => "xsd-schema"}, {41, repeated(@xsd, 20)}} ==
               module.get_issues(binary_result, %{}, pagination_config)

      assert {%{"issues_category" => "xsd-schema"}, {41, repeated(@xsd, 20)}} ==
               module.get_issues(binary_result, %{"issues_category" => "xsd-schema"}, pagination_config)

      assert {%{"issues_category" => "base-rules"}, {41, repeated(@rule, 20)}} ==
               module.get_issues(binary_result, %{"issues_category" => "base-rules"}, pagination_config)

      pagination_config = make_pagination_config(%{"page" => "3"})

      assert {%{"issues_category" => "xsd-schema"}, {41, repeated(@xsd, 1)}} ==
               module.get_issues(binary_result, %{}, pagination_config)

      assert {%{"issues_category" => "xsd-schema"}, {41, repeated(@xsd, 1)}} ==
               module.get_issues(binary_result, %{"issues_category" => "xsd-schema"}, pagination_config)

      assert {%{"issues_category" => "base-rules"}, {41, repeated(@rule, 1)}} ==
               module.get_issues(binary_result, %{"issues_category" => "base-rules"}, pagination_config)
    end
  end

  test "get_issues from binary, no error" do
    for module <- [V0_2_1, V0_2_2] do
      pagination_config = make_pagination_config(%{})

      binary_result =
        result_factory("base-rules": 0, "xsd-schema": 0)
        |> module.to_binary_result()

      assert {%{"issues_category" => "xsd-schema"}, {0, repeated(@xsd, 0)}} ==
               module.get_issues(binary_result, %{}, pagination_config)

      assert {%{"issues_category" => "xsd-schema"}, {0, repeated(@xsd, 0)}} ==
               module.get_issues(binary_result, %{"issues_category" => "xsd-schema"}, pagination_config)

      assert {%{"issues_category" => "base-rules"}, {0, repeated(@rule, 0)}} ==
               module.get_issues(binary_result, %{"issues_category" => "base-rules"}, pagination_config)

      pagination_config = make_pagination_config(%{"page" => "3"})

      assert {%{"issues_category" => "xsd-schema"}, {0, repeated(@xsd, 0)}} ==
               module.get_issues(binary_result, %{}, pagination_config)

      assert {%{"issues_category" => "xsd-schema"}, {0, repeated(@xsd, 0)}} ==
               module.get_issues(binary_result, %{"issues_category" => "xsd-schema"}, pagination_config)

      assert {%{"issues_category" => "base-rules"}, {0, repeated(@rule, 0)}} ==
               module.get_issues(binary_result, %{"issues_category" => "base-rules"}, pagination_config)
    end
  end

  describe "summary_from_binary/1" do
    test "counts only the most severe level per category" do
      assert_summary_from_binary(V0_2_1, [
        {"xsd-schema", %{"count" => 1, "criticity" => "error"}},
        {"base-rules", %{"count" => 1, "criticity" => "warning"}}
      ])
    end

    test "empty binary returns all categories with count 0 and NoError" do
      assert_summary_from_binary_empty(V0_2_1, ["xsd-schema", "french-profile", "base-rules"])
    end
  end

  defp result_factory(counts) do
    counts
    |> Enum.flat_map(fn {category, count} ->
      error_factory(category, count)
    end)
  end

  defp error_factory(:"xsd-schema", count), do: repeated(@xsd, count)
  defp error_factory(:"base-rules", count), do: repeated(@rule, count)
  defp error_factory(_, _), do: []

  defp repeated(item, times) do
    [item]
    |> Stream.cycle()
    |> Enum.take(times)
  end
end
