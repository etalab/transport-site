defmodule Datagouvfr.Client.CommunityResources do
  @moduledoc """
  Helper to access to GET /api/1/community_resources/?dataset=id
  """
  import Datagouvfr.Client, only: [get_request: 2]
  require Logger

  def get(conn, id) do
    conn
    |> get_request("/datasets/community_resources/?dataset=#{id}")
    |> case do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, error} ->
        Logger.error("When getting community_ressources for id #{id}: #{error.reason}")
        {:error, []}
    end
  end
end
