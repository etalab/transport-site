defmodule Transport.Test.Validators.NeTEx.SummaryFromBinary do
  @moduledoc """
  Shared helpers for testing `summary_from_binary/1` across adapter modules.
  """
  import ExUnit.Assertions

  def expect_stats(summary, category, expected) do
    stat = Enum.find(summary, &(&1["category"] == category))["stats"]
    assert stat == expected
  end

  def assert_summary_from_binary(adapter, categories_and_stats) do
    errors = %{
      "xsd-schema" => [%{"code" => "xsd-1", "criticity" => "error"}],
      "base-rules" => [%{"code" => "rule-1", "criticity" => "warning"}]
    }

    summary = errors |> adapter.to_binary_result() |> adapter.summary_from_binary()

    for {category, expected} <- categories_and_stats do
      expect_stats(summary, category, expected)
    end
  end

  def assert_summary_from_binary_empty(adapter, category_names) do
    summary = %{} |> adapter.to_binary_result() |> adapter.summary_from_binary()

    assert length(summary) == length(category_names)

    for category <- category_names do
      expect_stats(summary, category, %{"count" => 0, "criticity" => "NoError"})
    end
  end
end
