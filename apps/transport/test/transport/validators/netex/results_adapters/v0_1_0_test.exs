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
      result_factory("xsd-123": 41, "valid-day-bits": 41)
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
    |> Enum.map(fn {category, count} ->
      {Atom.to_string(category), error_factory(category, count)}
    end)
    |> Map.new()
  end

  defp error_factory(:"xsd-123", count), do: repeated(@xsd, count)
  defp error_factory(:"valid-day-bits", count), do: repeated(@rule, count)
  defp error_factory(_, _), do: []

  defp repeated(item, times) do
    [item]
    |> Stream.cycle()
    |> Enum.take(times)
  end
end
