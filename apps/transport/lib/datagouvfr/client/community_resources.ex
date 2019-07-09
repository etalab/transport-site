defmodule Datagouvfr.Client.CommunityResources do
  @moduledoc """
  Helper to access to GET /api/1/community_resources/?dataset=id
  """
  alias Datagouvfr.Client
  require Logger

  @endpoint "/datasets/community_resources/"

  def get(id) do
    "#{@endpoint}?dataset=#{id}"
    |> Client.get()
    |> case do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, error} ->
        Logger.error("When getting community_ressources for id #{id}: #{error.reason}")
        {:error, []}
    end
  end
end
