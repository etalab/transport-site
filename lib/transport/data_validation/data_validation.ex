defmodule Transport.DataValidation do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.{CreateProject, ValidateFeedVersion}

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
  Validates a feed version.
  """
  @spec validate_feed_version(Project.t, map()) :: :ok | {:error, any()}
  def validate_feed_version(%Project{} = %{name: name} = project, %{} = params) when is_binary(name) do
    params
    |> ValidateFeedVersion.new
    |> ValidateFeedVersion.validate
    |> case do
      {:ok, command} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
