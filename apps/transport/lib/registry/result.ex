defmodule Transport.Registry.Result do
  @moduledoc """
  Type and utilities to represent results.
  """
  require Integer

  @type t(positive) :: {:ok, positive} | {:error, binary()}

  def ok(positive), do: {:ok, positive}

  def error(message), do: {:error, message}

  @doc """
  iex> [{:ok, "valid"}, {:error, "invalid"}, {:ok, "relevant"}] |> cat_results()
  ["valid", "relevant"]
  """
  @spec cat_results(Enumerable.t(t(term()))) :: Enumerable.t(term())
  def cat_results(enumerable), do: Stream.flat_map(enumerable, &keep_ok/1)

  defp keep_ok({:ok, result}), do: [result]
  defp keep_ok(_), do: []

  @doc """
  iex> 1..10 |> map_result(fn v -> if Integer.is_odd(v) do {:ok, v} else {:error, "Even Steven"} end end)
  [1, 3, 5, 7, 9]
  """
  @spec map_result(Enumerable.t(term()), (term() -> t(term()))) :: Enumerable.t(term())
  def map_result(enumerable, mapper) do
    enumerable
    |> Stream.map(mapper)
    |> cat_results()
  end
end
