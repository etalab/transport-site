defmodule Transport.DataValidation.Repository.ProjectRepository do
  @moduledoc """
  A project repository to interact with datatools.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.CreateProject

  @endpoint Application.get_env(:transport, :datatools_url) <> "/api/manager/secure/project"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error

  @doc """
  Finds a project (by name).
  """
  @spec execute(FindProject.t) :: {:ok, Project.t} | {:ok, nil} | {:error, any()}
  def execute(%FindProject{} = query) do
    with {:ok, %@res{status_code: 200, body: body}} <- @client.get(@endpoint),
         {:ok, projects} <- Poison.decode(body, as: [%Project{}]),
         project <- Enum.find(projects, &(&1.name == query.name)) do
      {:ok, project}
    else
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a project.
  """
  @spec execute(CreateProject.t) :: {:ok, Project.t} | {:error, any()}
  def execute(%CreateProject{} = command) do
    with {:ok, body} <- Poison.encode(command),
         {:ok, %@res{status_code: 200, body: body}} <- @client.post(@endpoint, body) do
      Poison.decode(body, as: %Project{})
    else
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end
end
