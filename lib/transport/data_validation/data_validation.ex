defmodule Transport.DataValidation do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.CreateProject

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
  @spec create_project(map()) :: {:ok, Project.t} | {:error, any()}
  def create_project(%{} = params) do
    params
    |> CreateProject.new
    |> CreateProject.validate
    |> case do
      {:ok, command} -> Project.execute(command)
      {:error, error} -> {:error, error}
    end
  end
end
