defmodule Transport.Registry.ExtractorTest do
  use ExUnit.Case, async: false

  require Integer
  alias Transport.Registry.Extractor

  test "keep_results" do
    assert [] == keep_results([])
    assert [] == keep_results([{:error, "Error message"}])
    assert [1, 3] == keep_results([{:ok, 1}, {:error, "Error message"}, {:ok, 3}])
  end

  test "traverse" do
    assert [] == traverse([], &even_is_forbidden/1)
    assert [1, 3, 5, 7, 9] == traverse(1..10, &even_is_forbidden/1)
  end

  defp keep_results(enumerable) do
    enumerable |> Extractor.keep_results() |> Enum.to_list()
  end

  defp traverse(enumerable, mapper) do
    enumerable |> Extractor.traverse(mapper) |> Enum.to_list()
  end

  defp even_is_forbidden(i) when Integer.is_odd(i), do: {:ok, i}
  defp even_is_forbidden(_), do: {:error, "Even is forbidden"}
end
