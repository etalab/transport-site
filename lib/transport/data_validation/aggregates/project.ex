defmodule Transport.DataValidation.Aggregates.Project do
  @moduledoc """
  A project is a container of feed sources and its versions.
  """

  defstruct [:id, :name]

  use GenServer
  use ExConstructor
  alias Transport.DataValidation.Supervisor
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.{CreateProject, ValidateFeedVersion}
  alias Transport.DataValidation.Repository.{ProjectRepository, FeedVersionRepository}

  @registry :data_validation_project_registry

  @type t :: %__MODULE__{
    id: String.t,
    name: String.t
  }

  def start_link(name) when is_binary(name) do
    GenServer.start_link(
      __MODULE__,
      %__MODULE__{name: name},
      name: {:via, Registry, {:data_validation_project_registry, name}}
    )
  end

  def init(%__MODULE__{} = project) do
    {:ok, project}
  end

  def execute(%FindProject{} = query) do
    {:ok, pid} = get_pid(query.name)
    GenServer.call(pid, {:find_project, query})
  end

  def execute(%CreateProject{} = command) do
    {:ok, pid} = get_pid(command.name)
    GenServer.call(pid, {:create_project, command})
  end

  def execute(%ValidateFeedVersion{} = command) do
    {:ok, pid} = get_pid(command.project.name)
    GenServer.call(pid, {:validate_feed_version, command})
  end

  def handle_call({:find_project, query}, _from, %__MODULE__{id: nil} = project) do
    case ProjectRepository.execute(query) do
      {:ok, nil} -> {:reply, {:ok, nil}, project}
      {:ok, project} -> {:reply, {:ok, project}, project}
      {:error, error} -> {:reply, {:error, error}, project}
    end
  end

  def handle_call({:find_project, _query}, _from, %__MODULE__{} = project) do
    {:reply, {:ok, project}, project}
  end

  def handle_call({:create_project, %CreateProject{} = command}, _from, %__MODULE__{id: nil} = project) do
    case ProjectRepository.execute(command) do
      {:ok, project} -> {:reply, {:ok, project}, project}
      {:error, error} -> {:reply, {:error, error}, project}
    end
  end

  def handle_call({:create_project, %CreateProject{}}, _from, %__MODULE__{} = project) do
    {:reply, {:ok, project}, project}
  end

  def handle_call({:validate_feed_version, %ValidateFeedVersion{} = command}, _from, %__MODULE__{} = project) do
    case FeedVersionRepository.execute(command) do
      {:ok, _} -> {:reply, {:ok, project}, project}
      {:error, error} -> {:reply, {:error, error}, project}
    end
  end

  def handle_call({:validate_feed_version, %ValidateFeedVersion{} = command}, _from, %__MODULE__{} = project) do
    {:reply, {:ok, project}, project}
  end

  # private

  defp get_pid(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> Supervisor.start_project(name)
    end
  end
end
