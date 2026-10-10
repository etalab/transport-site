defmodule Transport.Test.Validators.NeTEx.SummaryByCategoryHelpers do
  @moduledoc """
  Shared helpers for testing `summary_by_category/1` across adapter modules.
  """
  import ExUnit.Assertions

  def expect_stats(summary, category, expected) do
    stat = Enum.find(summary, &(&1["category"] == category))["stats"]
    assert stat == expected
  end

  def assert_summary_by_category(adapter, categories_and_stats) do
    errors = [%{"code" => "xsd-1", "criticity" => "error"}, %{"code" => "rule-1", "criticity" => "warning"}]

    summary = adapter.to_dataframe(errors) |> adapter.summary_by_category()

    for {category, expected} <- categories_and_stats do
      expect_stats(summary, category, expected)
    end
  end

  def assert_summary_by_category_empty(adapter, category_names) do
    summary = [] |> adapter.to_dataframe() |> adapter.summary_by_category()

    assert length(summary) == length(category_names)

    for category <- category_names do
      expect_stats(summary, category, %{"count" => 0, "criticity" => "NoError"})
    end
  end
end
