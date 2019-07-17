defmodule Datagouvfr.Client.CommunityResources do
  @moduledoc """
  Helper to access to GET /api/1/community_resources/?dataset=id
  """
  alias Datagouvfr.Client.API
  require Logger

  @endpoint "/datasets/community_resources/"

  @spec get(binary) :: Client.response
  def get(id) when is_binary(id) do
    case API.get("#{@endpoint}?dataset=#{id}") do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:ok, data} ->
        Logger.error("When getting community_ressources for id #{id}: request was ok but the response didn't contain data #{data}")
        {:error, []}
      {:error, %{reason: reason}} ->
        Logger.error("When getting community_ressources for id #{id}: #{reason}")
        {:error, []}
      {:error, error} ->
        Logger.error("When getting community_ressources for id #{id}: #{error}")
        {:error, []}
    end
  end
end
