defmodule Transport.DataValidation.Repository.FeedSourceRepository do
  @moduledoc """
  A feed source repository to interact with datatools.
  """

  alias Transport.DataValidation.Aggregates.FeedSource
  alias Transport.DataValidation.Queries.FindFeedSource
  alias Transport.DataValidation.Commands.{CreateFeedSource, ValidateFeedSource}

  @endpoint Application.get_env(:transport, :datatools_url) <> "/api/manager/secure/feedsource"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error

  @doc """
  Finds a feed source (by project and by name).
  """
  @spec execute(FindFeedSource.t) :: {:ok, FeedSource.t} | {:ok, nil} | {:error, any()}
  def execute(%FindFeedSource{project: %{id: project_id}, name: name}) when is_binary(project_id) and is_binary(name) do
    with {:ok, %@res{status_code: 200, body: body}} <- @client.get(@endpoint <> "?projectId=#{project_id}"),
         {:ok, feed_sources} <- Poison.decode(body, as: [%FeedSource{}]),
         feed_source <- Enum.find(feed_sources, &(&1.name == name)) do
      {:ok, feed_source}
    else
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a feed source.
  """
  @spec execute(CreateFeedSource.t) :: {:ok, FeedSource.t} | {:error, any()}
  def execute(%CreateFeedSource{} = command) do
    with {:ok, representation} <- represent(command),
         {:ok, body} <- Poison.encode(representation),
         {:ok, %@res{status_code: 200, body: body}} <- @client.post(@endpoint, body) do
      Poison.decode(body, as: %FeedSource{})
    else
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Validates a feed source.
  """
  @spec execute(ValidateFeedSource.t) :: :ok | {:error, any()}
  def execute(%ValidateFeedSource{} = command) do
    case @client.post(@endpoint <> "/#{command.feed_source.id}/fetch?projectId=#{command.project.id}", []) do
      {:ok, %@res{status_code: 200}} ->
        :ok
      {:ok, %@res{body: body}} ->
        {:ok, %{"message" => error}} = Poison.decode(body)
        {:error, error}
      {:error, %@err{reason: error}} ->
        {:error, error}
      {:error, error} ->
        {:error, error}
    end
  end

  # private

  defp represent(action) do
    {:ok, %{"projectId" => action.project.id, "name" => action.name, "url" => action.url}}
  end
end
