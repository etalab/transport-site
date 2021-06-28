defmodule Datagouvfr.Client.CommunityResources do
  @moduledoc """
    This behaviour defines the API for interacting with data.gouv community resources
    , with alternative implementations.
  """
  alias Datagouvfr.Client.API

  @callback get(dataset_id :: binary()) :: API.response()
  @callback delete(dataset_id :: binary(), resource_id :: binary()) ::
              {:ok, any()} | {:error, any()}

  defp impl, do: Application.get_env(:datagouvfr, :community_resources_impl)
  def get(dataset_id), do: impl().get(dataset_id)
  def delete(dataset_id, resource_id), do: impl().delete(dataset_id, resource_id)
end

defmodule Datagouvfr.Client.CommunityResources.API do
  @moduledoc """
    Actual implementation to intercat with community resources through data.gouv.fr API
  """
  require Logger

  @behaviour Datagouvfr.Client.CommunityResources
  @endpoint "/datasets/community_resources/"

  @spec get(binary) :: Datagouvfr.Client.API.response()
  def get(id) when is_binary(id) do
    case Datagouvfr.Client.API.get("#{@endpoint}?dataset=#{id}") do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:ok, data} ->
        Logger.error(
          "When getting community_ressources for id #{id}: request was ok but the response didn't contain data #{data}"
        )

        {:error, []}

      {:error, %{reason: reason}} ->
        Logger.error("When getting community_ressources for id #{id}: #{reason}")
        {:error, []}

      {:error, error} ->
        Logger.error("When getting community_ressources for id #{id}: #{error}")
        {:error, []}
    end
  end

  def delete(dataset_datagouv_id, resource_datagouv_id) do
    path = "#{@endpoint}/#{resource_datagouv_id}?dataset=#{dataset_datagouv_id}"
    headers = [Datagouvfr.Client.API.api_key_headers()]

    Datagouvfr.Client.API.delete(path, headers)
  end
end

defmodule Datagouvfr.Client.CommunityResources.Mock do
  @moduledoc """
    A mock used for testing
  """
  @behaviour Datagouvfr.Client.CommunityResources

  def get(_dataset_id) do
    {:ok, []}
  end

  def delete(_dataset_id, _resource_id) do
    {:ok, ""}
  end
end
