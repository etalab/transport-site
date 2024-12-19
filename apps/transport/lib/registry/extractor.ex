defmodule Transport.Registry.Extractor do
  @moduledoc """
  Interface and utilities for stops extractors.
  """

  require Logger

  alias Transport.Registry.Model.Stop

  @type result(positive) :: {:ok, positive} | {:error, binary()}

  @callback extract_from_archive(path :: Path.t()) :: result([Stop.t()])

  @spec cat_results(Stream.t(result(term()))) :: Stream.t(term())
  def cat_results(enumerable), do: Stream.flat_map(enumerable, &keep_ok/1)

  defp keep_ok({:ok, result}), do: [result]
  defp keep_ok(_), do: []

  @spec map_result(Stream.t(term()), (term() -> result(term()))) :: Stream.t(term())
  def map_result(enumerable, mapper) do
    enumerable
    |> Stream.map(mapper)
    |> cat_results()
  end
end
