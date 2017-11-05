defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData context.
  """

  alias Transport.ReusableData.Dataset

  @pool DBConnection.Poolboy

  @doc """
  Returns the list of reusable datasets.

  ## Examples

      iex> ReusableData.create_dataset(%{title: "Leningrad metro dataset", anomalies: [], download_uri: "link.to"})
      iex> ReusableData.list_datasets()
      ...> |> List.first
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

  """
  @spec list_datasets() :: [%Dataset{}]
  def list_datasets do
    query = %{anomalies: [], download_uri: %{"$ne" => nil}}

    :mongo
    |> Mongo.find("datasets", query, pool: @pool)
    |> Enum.to_list()
    |> Enum.map(&Dataset.new(&1))
  end


  @doc """
  Return one dataset.

  ## Examples

    iex> ResuableData.get_dataset("leningrad")
    %Dataset{slug: "leningrad", title: "Leningrad metro dataset", ...]

  """
  @spec get_dataset(String.t) :: %Dataset{}
  def get_dataset(slug) do
    query = %{slug: slug}

    :mongo
    |> Mongo.find_one("datasets", query, pool: @pool)
    |> case do
      nil -> nil
      dataset -> Dataset.new(dataset)
    end
  end

  @doc """
  Creates a dataset.

  ## Examples

      iex> ReusableData.create_dataset(%{title: "Saintes"})
      ...> |> Map.get(:title)
      "Saintes"

  """
  @spec create_dataset(map()) :: %Dataset{}
  def create_dataset(%{} = attrs) do
    {:ok, result} = Mongo.insert_one(:mongo, "datasets", attrs, pool: @pool)
    query         = %{"_id"  => result.inserted_id}

    :mongo
    |> Mongo.find_one("datasets", query, pool: @pool)
    |> Dataset.new
  end

  @doc """
  Updates a dataset.

  ## Examples

      iex> ReusableData.create_dataset(%{title: "Creative title"})
      ...> |> ReusableData.update_dataset(%{title: "Lame title"})
      :ok

      iex> ReusableData.update_dataset(%Dataset{}, %{title: "Alphaville"})
      {:error, :enodoc}

  """
  @spec update_dataset(%Dataset{}, map()) :: :ok | {:error, :enodoc}
  def update_dataset(%Dataset{} = dataset, %{} = attrs) do
    query     = %{"_id"  => dataset._id}
    changeset = %{"$set" => attrs}

    :mongo
    |> Mongo.find_one_and_update("datasets", query, changeset, pool: @pool)
    |> case do
      {:ok, nil} -> {:error, :enodoc}
      {:ok, _}   -> :ok
    end
  end
end
