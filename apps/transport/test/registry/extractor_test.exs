defmodule Transport.Registry.ExtractorTest do
  use ExUnit.Case, async: false

  require Integer
  alias Transport.Registry.Extractor

  test "cat_results" do
    assert [] == cat_results([])
    assert [] == cat_results([{:error, "Error message"}])
    assert [1, 3] == cat_results([{:ok, 1}, {:error, "Error message"}, {:ok, 3}])
  end

  test "map_result" do
    assert [] == map_result([], &even_is_forbidden/1)
    assert [1, 3, 5, 7, 9] == map_result(1..10, &even_is_forbidden/1)
  end

  defp cat_results(enumerable) do
    enumerable |> Extractor.cat_results() |> Enum.to_list()
  end

  defp map_result(enumerable, mapper) do
    enumerable |> Extractor.map_result(mapper) |> Enum.to_list()
  end

  defp even_is_forbidden(i) when Integer.is_odd(i), do: {:ok, i}
  defp even_is_forbidden(_), do: {:error, "Even is forbidden"}
end
