defmodule Transport.DataValidation.Repository.ProjectRepository do
  @moduledoc """
  A project repository to interact with datatools.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.CreateProject

  @endpoint Application.get_env(:transport, :datatools_url) <> "/api/manager/secure/project"

  @doc """
  Finds a project by name.
  """
  @spec find(FindProject.t) :: {:ok, Project.t} | {:ok, nil} | {:error, any()}
  def find(%FindProject{name: name}) when not is_nil(name) do
    case HTTPoison.get(@endpoint) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        project =
          body
          |> Poison.decode!(as: [%Project{}])
          |> Enum.find(&(&1.name == name))

        {:ok, project}
      {:error, %HTTPoison.Error{reason: error}} ->
        {:error, error}
    end
  end

  @doc """
  Creates a project.
  """
  @spec create(CreateProject.t) :: {:ok, Project.t} | {:error, any()}
  def create(%CreateProject{} = command) do
    case HTTPoison.post(@endpoint, Poison.encode!(command)) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Poison.decode!(body, as: %Project{})}
      {:error, %HTTPoison.Error{reason: error}} ->
        {:error, error}
    end
  end
end
