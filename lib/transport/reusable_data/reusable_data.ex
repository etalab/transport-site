defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData context.
  """

  alias Transport.ReusableData.Dataset

  @pool DBConnection.Poolboy

  @doc """
  Returns the list of reusable datasets.

  ## Examples

      iex> ReusableData.list_datasets()
      [%Dataset{title: "Leningrad metro dataset", anomalies: []}, ...]

  """
  @spec list_datasets() :: [%Dataset{}]
  def list_datasets do
    query = %{anomalies: [], download_uri: %{"$ne" => nil}}

    :mongo
    |> Mongo.find("datasets", query, pool: @pool)
    |> Enum.to_list()
    |> Enum.map(&structify(&1, %Dataset{}))
  end

  @doc """
  Updates a dataset.

  ## Examples

      iex> update_dataset(existing_dataset, %{field: new_value})
      :ok

      iex> update_dataset(non_existing_dataset, %{field: new_value})
      {:error, :nodocument}

  """
  @spec update_dataset(%Dataset{}, map()) :: :ok | {:error, :nodocument}
  def update_dataset(%Dataset{} = dataset, attrs) do
    query     = %{"_id"  => dataset._id}
    changeset = %{"$set" => attrs}

    :mongo
    |> Mongo.find_one_and_update("datasets", query, changeset, pool: @pool)
    |> case do
      {:ok, nil} -> {:error, :nodocument}
      {:ok, _}   -> :ok
    end
  end

  # private

  defp structify(document, struct) do
    Enum.reduce(document, struct, fn({key, value}, map) ->
      Map.put(map, String.to_existing_atom(key), value)
    end)
  end
end
