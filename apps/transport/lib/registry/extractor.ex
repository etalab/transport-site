defmodule Transport.Registry.Extractor do
  @moduledoc """
  Interface and utilities for stops extractors.
  """

  require Logger

  alias Transport.Registry.Model.Stop

  @type result(positive) :: {:ok, positive} | {:error, binary()}

  @callback extract_from_archive(path :: Path.t()) :: result([Stop.t()])

  def keep_results(enumerable), do: Stream.flat_map(enumerable, &keep_result/1)

  defp keep_result({:ok, result}), do: [result]
  defp keep_result(_), do: []

  def traverse(enumerable, mapper) do
    enumerable
    |> Stream.map(mapper)
    |> keep_results()
  end
end
