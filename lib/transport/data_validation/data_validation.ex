defmodule Transport.DataValidation do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Commands.CreateProject

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
