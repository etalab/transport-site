defmodule Transport.DataValidation.Repository.FeedSourceRepository do
  @moduledoc """
  A feed source repository to interact with datatools.
  """

  alias Transport.DataValidation.Aggregates.FeedSource
  alias Transport.DataValidation.Commands.CreateFeedSource

  @endpoint Application.get_env(:transport, :datatools_url) <> "/api/manager/secure/feedsource"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error

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

  # private

  defp represent(%CreateFeedSource{} = command) do
    {:ok, %{"projectId" => command.project.id, "name" => command.name}}
  end
end
