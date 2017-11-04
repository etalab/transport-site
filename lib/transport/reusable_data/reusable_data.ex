defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData context.
  """

  alias Transport.ReusableData.Dataset

  @doc """
  Returns the list of datasets.

  ## Examples

      iex> list_datasets()
      [%Dataset{}, ...]

  """
  def list_datasets do
    :mongo
    |> Mongo.find("datasets", %{anomalies: []}, pool: DBConnection.Poolboy)
    |> Enum.to_list()
    |> Enum.map(fn(dataset) ->
      Enum.reduce(dataset, %Dataset{}, fn({key, value}, map) ->
        Map.put(map, String.to_existing_atom(key), value)
      end)
    end)
  end
end
