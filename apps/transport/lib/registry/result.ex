defmodule Transport.Registry.Result do
  @moduledoc """
  Type and utilities to represent results.
  """

  @type t(positive) :: {:ok, positive} | {:error, binary()}

  def ok(positive), do: {:ok, positive}

  def error(message), do: {:error, message}

  @spec cat_results(Stream.t(t(term()))) :: Stream.t(term())
  def cat_results(enumerable), do: Stream.flat_map(enumerable, &keep_ok/1)

  defp keep_ok({:ok, result}), do: [result]
  defp keep_ok(_), do: []

  @spec map_result(Stream.t(term()), (term() -> t(term()))) :: Stream.t(term())
  def map_result(enumerable, mapper) do
    enumerable
    |> Stream.map(mapper)
    |> cat_results()
  end
end
