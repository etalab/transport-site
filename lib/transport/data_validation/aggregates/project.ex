defmodule Transport.DataValidation.Aggregates.Project do
  @moduledoc """
  A project is a container of feed sources and its versions.
  """

  defstruct [:id, :name]

  use GenServer
  use ExConstructor
  alias Transport.DataValidation.Supervisor
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.CreateProject
  alias Transport.DataValidation.Repository.ProjectRepository

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
    GenServer.cast(self(), {:populate_project, %FindProject{name: project.name}})
    {:ok, project}
  end

  def execute(%FindProject{} = query) do
    {:ok, pid} = get_pid(query.name)
    GenServer.call(pid, {:find_project})
  end

  def execute(%CreateProject{} = command) do
    {:ok, pid} = get_pid(command.name)
    GenServer.cast(pid, {:create_project, command})
  end

  def handle_call({:find_project}, _from, %__MODULE__{} = project) do
    {:reply, {:ok, project}, project}
  end

  def handle_cast({:create_project, %CreateProject{} = command}, %__MODULE__{id: nil} = project) do
    case ProjectRepository.create(command) do
      {:ok, project} -> {:noreply, project}
      {:error, error} -> {:stop, error, project}
    end
  end

  def handle_cast({:create_project, %CreateProject{}}, %__MODULE__{} = project) do
    {:noreply, project}
  end

  def handle_cast({:populate_project, %FindProject{} = query}, %__MODULE__{} = project) do
    case ProjectRepository.find(query) do
      {:ok, nil} -> {:noreply, project}
      {:ok, project} -> {:noreply, project}
      {:error, error} -> {:stop, error, project}
    end
  end

  # private

  defp get_pid(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> Supervisor.start_project(name)
    end
  end
end
