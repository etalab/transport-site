defmodule Transport.ImportDataWorker do
  @moduledoc """
  ImportDataworker to launch importation and validation tasks
  """
  use GenServer

  alias DB.{Dataset, Repo, Resource}
  alias Transport.ImportData
  require Logger

  ## API ##

  @spec import_validate_all :: :ok
  def import_validate_all do
    Dataset
    |> Repo.all()
    |> Enum.each(fn dataset -> GenServer.cast(__MODULE__, {:import_and_validation, dataset}) end)
  end

  @spec validate_all :: :ok
  def validate_all do
    Dataset
    |> Repo.all()
    |> Enum.each(fn dataset -> GenServer.cast(__MODULE__, {:validate_all, dataset}) end)
  end

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## GenServer implementations

  @impl true
  def init(stack) do
    {:ok, stack}
  end

  @impl true
  def handle_cast({:import_and_validation, %Dataset{id: id} = dataset}, state) do
    ImportData.import_dataset(dataset)
    queue_validations(dataset)
    {:noreply, state}
  rescue
    e -> Logger.error("error in the import data worker for dataset #{id}: #{inspect(e)}")
  end

  @impl true
  def handle_cast({:validate, %Resource{id: id} = resource}, state) do
    Resource.validate_and_save(resource)

    {:noreply, state}
  rescue
    e -> Logger.error("error in the import data worker validation for resource #{id}: #{inspect(e)}")
  end

  @impl true
  def handle_cast({:validate_all, dataset}, state) do
    queue_validations(dataset)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  @spec queue_validations(Dataset.t()) :: :ok
  defp queue_validations(dataset) do
    dataset
    |> Repo.preload(:resources)
    |> Map.get(:resources)
    |> Enum.each(fn resource -> GenServer.cast(__MODULE__, {:validate, resource}) end)
  end
end
