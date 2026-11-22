defmodule Transport.Test.Validators.NeTEx.SummaryByCategoryHelpers do
  @moduledoc """
  Shared helpers for testing `summary_by_category/1` across adapter modules.
  """
  import ExUnit.Assertions, only: [assert: 1]

  def assert_summary_by_category(adapter, categories_and_stats) do
    errors = [
      %{"code" => "xsd-1", "criticity" => "error"},
      %{"code" => "rule-1", "criticity" => "warning"}
    ]

    summary = adapter.to_dataframe(errors) |> adapter.summary_by_category()

    for {category, expected} <- categories_and_stats do
      assert Enum.find(summary, &(&1["category"] == category))["stats"] == expected
    end
  end
end
