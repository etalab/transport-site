defmodule Transport.DataValidation.Aggregates.Project do
  @moduledoc """
  A project is a container of feed sources and its versions.
  """

  defstruct [:id, :name, feed_sources: []]

  use GenServer
  use ExConstructor
  alias Transport.DataValidation.Supervisor
  alias Transport.DataValidation.Aggregates.FeedSource
  alias Transport.DataValidation.Queries.{FindProject, FindFeedSource}
  alias Transport.DataValidation.Commands.{CreateProject, CreateFeedSource}
  alias Transport.DataValidation.Repository.{ProjectRepository, FeedSourceRepository}

  @registry :data_validation_project_registry

  @type t :: %__MODULE__{
    id: String.t,
    name: String.t,
    feed_sources: [FeedSource.t]
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

  def execute(%FindFeedSource{} = query) do
    {:ok, pid} = get_pid(query.project.name)
    GenServer.call(pid, {:find_feed_source, query})
  end

  def execute(%CreateFeedSource{} = command) do
    {:ok, pid} = get_pid(command.project.name)
    GenServer.call(pid, {:create_feed_source, command})
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

  def handle_call({:find_feed_source, %FindFeedSource{} = query}, _from, %__MODULE__{} = project) do
    case handle_feed_source_action(project, query) do
      {:ok, feed_source, project} -> {:reply, {:ok, feed_source}, project}
      {:ok, feed_source} -> {:reply, {:ok, feed_source}, project}
      {:error, error} -> {:reply, {:error, error}, project}
    end
  end

  def handle_call({:create_feed_source, %CreateFeedSource{} = command}, _from, %__MODULE__{} = project) do
    case handle_feed_source_action(project, command) do
      {:ok, feed_source, project} -> {:reply, {:ok, feed_source}, project}
      {:ok, feed_source} -> {:reply, {:ok, feed_source}, project}
      {:error, error} -> {:reply, {:error, error}, project}
    end
  end

  # private

  defp get_pid(name) when is_binary(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> Supervisor.start_project(name)
    end
  end

  defp handle_feed_source_action(%__MODULE__{} = project, action) do
    with nil <- Enum.find(project.feed_sources, &(&1.name == action.name)),
         {:ok, nil} <- FeedSourceRepository.execute(action) do
      {:ok, nil}
    else
      {:ok, feed_source} ->
        {:ok, feed_source, %{project | feed_sources: [feed_source | project.feed_sources]}}
      {:error, error} ->
        {:error, error}
      feed_source ->
        {:ok, feed_source}
    end
  end
end
