defmodule Transport.DataValidation do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.{CreateProject, CreateFeedSource}

  @doc """
  Finds a project.
  """
  @spec find_project(String.t) :: {:ok, Project.t} | {:error, any()}
  def find_project(name) when is_binary(name) do
    Project.execute(%FindProject{name: name})
  end

  @doc """
  Creates a new project.
  """
  @spec create_project(map()) :: :ok | {:error, any()}
  def create_project(%{} = params) do
    params
    |> CreateProject.new
    |> CreateProject.validate
    |> case do
      {:ok, command} -> Project.execute(command)
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a feed source.
  """
  @spec create_feed_source(map()) :: :ok | {:error, any()}
  def create_feed_source(%{} = params) do
    params
    |> CreateFeedSource.new
    |> CreateFeedSource.validate
    |> case do
      {:ok, command} -> Project.execute(command)
      {:error, error} -> {:error, error}
    end
  end
end
