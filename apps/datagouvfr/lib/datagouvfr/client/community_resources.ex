defmodule Datagouvfr.Client.CommunityResources do
  @moduledoc """
    This behaviour defines the API for interacting with data.gouv community resources
    , with alternative implementations.
  """

  @callback get(dataset_id :: binary()) :: {:ok, [any()]} | {:error, []}
  @callback delete(dataset_id :: binary(), resource_id :: binary()) ::
              {:ok, any()} | {:error, any()}

  defp impl, do: Application.get_env(:datagouvfr, :community_resources_impl)
  def get(dataset_id), do: impl().get(dataset_id)
  def delete(dataset_id, resource_id), do: impl().delete(dataset_id, resource_id)
end

defmodule Datagouvfr.Client.CommunityResources.API do
  @moduledoc """
    Actual implementation to interact with community resources through data.gouv.fr API
  """
  require Logger

  @behaviour Datagouvfr.Client.CommunityResources
  @endpoint "/datasets/community_resources/"

  @spec get(dataset_id :: binary()) :: {:ok, [any()]} | {:error, []}
  def get(dataset_id) when is_binary(dataset_id) do
    case Datagouvfr.Client.API.fetch_all_pages("#{@endpoint}?dataset=#{dataset_id}") do
      {:ok, pages} -> {:ok, pages}
      {:error, _error} -> {:error, []}
    end
  end

  def delete(dataset_datagouv_id, resource_datagouv_id) do
    path = "#{@endpoint}/#{resource_datagouv_id}?dataset=#{dataset_datagouv_id}"
    headers = [Datagouvfr.Client.API.api_key_headers()]

    Datagouvfr.Client.API.delete(path, headers)
  end
end

defmodule Datagouvfr.Client.StubCommunityResources do
  @moduledoc """
    A stub used for testing, when we don't really care about community resources
  """
  @behaviour Datagouvfr.Client.CommunityResources

  def get(_dataset_id) do
    {:ok, []}
  end

  def delete(_dataset_id, _resource_id) do
    {:ok, ""}
  end
end
