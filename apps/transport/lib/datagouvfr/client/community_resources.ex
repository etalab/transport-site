defmodule Datagouvfr.Client.CommunityResources do
  @moduledoc """
  Helper to access to GET /api/1/community_resources/?dataset=id
  """
  alias Datagouvfr.Client
  require Logger

  @endpoint "/datasets/community_resources/"

  @spec get(binary) :: {:error, []} | {:ok, any}
  def get(id) when is_binary(id) do
    case Client.get("#{@endpoint}?dataset=#{id}") do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, %{reason: reason}} ->
        Logger.error("When getting community_ressources for id #{id}: #{reason}")
        {:error, []}
      {:error, error} ->
        Logger.error("When getting community_ressources for id #{id}: #{error}")
        {:error, []}
    end
  end
end
