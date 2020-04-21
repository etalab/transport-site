defmodule Transport.ImportDataWorker do
  @moduledoc """
  ImportDataworker to launch importation and validation tasks
  """
  use GenServer
  alias Transport.ImportData
  require Logger

  ## API ##

  @spec import_validate_all :: :ok
  def import_validate_all do
    GenServer.cast(__MODULE__, {:import_and_validation})
  end

  @spec validate_all :: :ok
  def validate_all do
    GenServer.cast(__MODULE__, {:validate_all})
  end

  @spec validate_all :: :ok
  def force_validate_all do
    GenServer.cast(__MODULE__, {:force_validate_all})
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
  def handle_cast({:import_and_validation}, state) do
    ImportData.import_validate_all()
    {:noreply, state}
  rescue
    e -> Logger.error("error in the import data worker : #{inspect(e)}")
  end

  @impl true
  def handle_cast({:validate_all}, state) do
    ImportData.validate_all_resources()
    {:noreply, state}
  rescue
    e -> Logger.error("error in the validation data worker : #{inspect(e)}")
  end

  @impl true
  def handle_cast({:force_validate_all}, state) do
    ImportData.validate_all_resources(true)
    {:noreply, state}
  rescue
    e -> Logger.error("error in the validation data worker : #{inspect(e)}")
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
