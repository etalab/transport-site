defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData bounded context.
  """

  alias Transport.ReusableData.{Dataset, Licence}
  require Logger

  @pool DBConnection.Poolboy

  @doc """
  Returns the list of reusable datasets filtered by a full text search.

  ## Examples

      iex> ReusableData.search_datasets("metro")
      ...> |> List.first
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

      iex> ReusableData.search_datasets("hyperloop express")
      []

  """
  @spec search_datasets(String.t) :: [%Dataset{}]
  def search_datasets(q) when is_binary(q) do
    query_datasets(%{
      # We display also datasets with anomalies
      # anomalies: [],
      coordinates: %{"$ne" => nil},
      download_url: %{"$ne" => nil},
      "$text": %{"$search" => q}
    })
  end

  @doc """
  Returns the list of reusable datasets containing no validation errors.

  ## Examples

      iex> ReusableData.list_datasets
      ...> |> List.first
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

  """
  @spec list_datasets :: [%Dataset{}]
  def list_datasets do
    query_datasets(%{
      # We display also datasets with anomalies
      # anomalies: [],
      download_url: %{"$ne" => nil}
    })
  end

  @doc """
  Return one dataset by id

  ## Examples

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

      iex> ReusableData.get_dataset("")
      nil

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset
      ...> |> Map.get(:valid?)
      true

  """
  @spec get_dataset(String.t) :: %Dataset{}
  def get_dataset(slug) do
    query = %{slug: slug}

    :mongo
    |> Mongo.find_one("datasets", query, pool: @pool)
    |> case do
      nil ->
        nil

      dataset ->
        dataset
        |> Dataset.new
        |> Dataset.assign(:error_count)
        |> Dataset.assign(:fatal_count)
        |> Dataset.assign(:notice_count)
        |> Dataset.assign(:warning_count)
        |> Dataset.assign(:group_validations)
        |> Dataset.assign(:valid?)
    end
  end

  @doc """
  Creates a dataset.

  ## Examples

      iex> %{title: "Saintes"}
      ...> |> ReusableData.create_dataset
      ...> |> Map.get(:title)
      "Saintes"

      iex> %{"title" => "Rochefort"}
      ...> |> ReusableData.create_dataset
      ...> |> Map.get(:title)
      "Rochefort"

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

      iex> %{title: "Creative title"}
      ...> |> ReusableData.create_dataset
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

  @doc """
  Builds a licence.

  ## Examples

      iex> %{name: "fr-lo"}
      ...> |> ReusableData.build_licence
      ...> |> Map.get(:name)
      "Open Licence"

      iex> %{name: "Libertarian"}
      ...> |> ReusableData.build_licence
      ...> |> Map.get(:name)
      nil

      iex> %{}
      ...> |> ReusableData.build_licence
      ...> |> Map.get(:alias)
      nil

  """
  @spec build_licence(map()) :: %Licence{}
  def build_licence(%{} = attrs) do
    Licence.new(attrs)
  end

  @doc """
  Returns the list of reusable datasets containing of a specific.

  ## Examples

      iex> ReusableData.list_datasets
      ...> |> List.first
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

  """
  @spec list_datasets(String.t) :: [%Dataset{}]
  def list_datasets(commune) do
    query_datasets(%{
      # We display also datasets with anomalies
      # anomalies: [],
      coordinates: %{"$ne" => nil},
      download_url: %{"$ne" => nil},
      commune_principale: String.to_integer commune
    })
  end

  def list_datasets_region(region) do
    query_datasets(%{
      # We display also datasets with anomalies
      # anomalies: [],
      coordinates: %{"$ne" => nil},
      download_url: %{"$ne" => nil},
      region: region
    })
  end

  @spec query_datasets(Map.t) :: [%Dataset{}]
  def query_datasets(%{} = query) do
    :mongo
    |> Mongo.find("datasets", query, pool: @pool)
    |> Enum.to_list()
    |> Enum.map(&Dataset.new(&1))
    |> Enum.reduce([], fn(dataset, acc) ->
      dataset =
        dataset
        |> Dataset.assign(:error_count)
        |> Dataset.assign(:fatal_count)
        |> Dataset.assign(:notice_count)
        |> Dataset.assign(:warning_count)
        |> Dataset.assign(:valid?)

      [dataset | acc]
    end)
    |> Enum.filter(&(&1.valid?))
  end
end
