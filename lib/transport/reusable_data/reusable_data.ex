defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData context.
  """

  alias Transport.ReusableData.Dataset
  alias Transport.Datagouvfr.Client.Datasets
  alias Transport.DataValidator.CeleryTask

  @pool DBConnection.Poolboy

  @doc """
  Returns the list of reusable datasets.

  ## Examples

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
  Return dataset by slug and its attached celery task.
  """
  @spec get_dataset(String.t, atom) :: %Dataset{}
  def get_dataset(slug, :with_celery_task) do
    with dataset <- get_dataset(slug),
         {:ok, celery_task} <- CeleryTask.find_one(dataset.celery_task_id) do
      Map.put(dataset, :celery_task, celery_task)
    end
  end

  @doc """
  Return one dataset by slug

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset
      ...> |> Map.get(:title)
      "Leningrad metro dataset"
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

      iex> %{title: "Saintes"}
      ...> |> ReusableData.create_dataset
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

  def get_dataset_id(conn, dataset) do
    conn
    |> Datasets.get(dataset.slug)
    |> case do
      {:ok, d}    -> d["id"]
      {:error, _} -> nil
    end
  end

  def count_errors(dataset) do
    dataset.celery_task.result
    |> Map.get("validations")
    |> Map.get("errors")
    |> Enum.count()
  end

  def count_warnings(dataset) do
    dataset.celery_task.result
    |> Map.get("validations")
    |> Map.get("warnings")
    |> Enum.count()
  end

  def count_notices(dataset) do
    dataset.celery_task.result
    |> Map.get("validations")
    |> Map.get("notices")
    |> Enum.count()
  end
end
