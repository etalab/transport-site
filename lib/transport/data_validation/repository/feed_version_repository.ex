defmodule Transport.DataValidation.Repository.FeedVersionRepository do
  @moduledoc """
  A feed version repository to interact with datatools.
  """

  alias Transport.DataValidation.Aggregates.FeedVersion
  alias Transport.DataValidation.Queries.FindFeedVersion

  @endpoint Application.get_env(:transport, :datatools_url) <> "/api/manager/secure/feedversion"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error

  @doc """
  Finds a feed version by its id.
  """
  @spec execute(FindFeedVersion.t) :: {:ok, FeedVersion.t} | {:ok, nil} | {:error, any()}
  def execute(
        %FindFeedVersion{
          project: %{id: project_id},
          latest_version_id: latest_version_id
        }
      )
      when is_binary(project_id) and is_binary(latest_version_id) do
    with {:ok, %@res{status_code: 200, body: body}} <- @client.get(@endpoint <> "/#{latest_version_id}"),
         {:ok, feed_version} <- Poison.decode(body, as: %FeedVersion{}) do
      {:ok, feed_version}
    else
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

end
