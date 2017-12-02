defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData bounded context.
  """

  alias Transport.ReusableData.{Dataset, Licence}
  alias Transport.Datagouvfr.Client.Datasets
  alias Transport.DataValidator.CeleryTask

  @pool DBConnection.Poolboy

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
    query = %{
      anomalies: [],
      coordinates: %{"$ne" => nil},
      download_uri: %{"$ne" => nil},
    }

    :mongo
    |> Mongo.find("datasets", query, pool: @pool)
    |> Enum.to_list()
    |> Enum.map(&Dataset.new(&1))
    |> Enum.reduce([], fn(dataset, acc) ->
      case CeleryTask.find_one(dataset.celery_task_id) do
        {:ok, task} -> [Map.put(dataset, :celery_task, task) | acc]
        _ -> acc
      end
    end)
    |> Enum.filter(&(count_errors(&1) == 0))
  end

  @doc """
  Return one dataset by slug

  ## Examples

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

      iex> ReusableData.get_dataset("")
      nil

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
  Return dataset by slug and its attached celery task.

  ## Examples

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset(:with_celery_task)
      ...> |> Map.get(:celery_task)
      ...> |> Map.get(:result)
      ...> |> Map.get("validations")
      ...> |> Map.get("errors")
      []

  """
  @spec get_dataset(String.t, :with_celery_task) :: %Dataset{}
  def get_dataset(slug, :with_celery_task) do
    with dataset <- get_dataset(slug),
         {:ok, celery_task} <- CeleryTask.find_one(dataset.celery_task_id) do
      Map.put(dataset, :celery_task, celery_task)
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
  Creates a dataset validation.

  ## Examples

      iex> %{status: "SUCCESS", result: "{}", children: "[]", traceback: "null"}
      ...> |> ReusableData.create_dataset_validation!
      ...> |> Map.get(:status)
      "SUCCESS"

      iex> %{}
      ...> |> ReusableData.create_dataset_validation!
      ** (ArgumentError) argument error
  """
  @spec create_dataset_validation!(map()) :: %CeleryTask{}
  def create_dataset_validation!(%{} = attrs) do
    case Mongo.insert_one(:mongo, "celery_taskmeta", attrs, pool: @pool) do
      {:ok, result} ->
        query = %{"_id"  => result.inserted_id}

        :mongo
        |> Mongo.find_one("celery_taskmeta", query, pool: @pool)
        |> CeleryTask.apply
        |> case do
          {:ok, celery_task} -> celery_task
          {:error, error} -> {:error, error}
        end

      {:error, error} -> {:error, error}
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
