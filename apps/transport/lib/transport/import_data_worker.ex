defmodule Transport.ImportDataWorker do
  @moduledoc """
  ImportDataworker to launch importation and validation tasks
  """
  use GenServer

  alias DB.{Dataset, Repo, Resource}
  alias Transport.ImportData

  ## API ##

  def all do
    Dataset
    |> Repo.all()
    |> Enum.each(fn dataset -> GenServer.cast(__MODULE__, {:import_and_validation, dataset}) end)
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
  def handle_cast({:import_and_validation, dataset}, state) do
    ImportData.call(dataset)
    queue_validations(dataset)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:validate, resource}, state) do
    Resource.validate_and_save(resource)

    {:noreply, state}
  end

  ## Private

  defp queue_validations(dataset) do
    dataset
    |> Repo.preload(:resources)
    |> Map.get(:resources)
    |> Enum.each(fn resource -> GenServer.cast(__MODULE__, {:validate, resource}) end)
  end
end
