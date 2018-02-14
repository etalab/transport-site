defmodule Transport.DataValidation do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Queries.{FindProject, FindFeedSource}
  alias Transport.DataValidation.Commands.{CreateProject, CreateFeedSource, ValidateFeedSource}

  @doc """
  Finds a project.
  """
  @spec find_project(map()) :: {:ok, Project.t} | {:error, any()}
  def find_project(%{} = params) do
    params
    |> FindProject.new
    |> Project.execute
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

  @doc """
  Finds a feed source.
  """
  @spec find_feed_source(map()) :: {:ok, FeedSource.t} | {:error, any()}
  def find_feed_source(%{} = params) do
    params
    |> FindFeedSource.new
    |> Project.execute
  end

  @doc """
  Creates a feed source.
  """
  @spec create_feed_source(map()) :: {:ok, FeedSource.t} | {:error, any()}
  def create_feed_source(%{} = params) do
    params
    |> CreateFeedSource.new
    |> CreateFeedSource.validate
    |> case do
      {:ok, command} -> Project.execute(command)
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Validates a feed source.
  """
  @spec validate_feed_source(map()) :: :ok | {:error, any()}
  def validate_feed_source(%{} = params) do
    params
    |> ValidateFeedSource.new
    |> ValidateFeedSource.validate
    |> case do
      {:ok, command} -> Project.execute(command)
      {:error, error} -> {:error, error}
    end
  end
end
