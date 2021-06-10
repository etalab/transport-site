defmodule Unlock.Config do
  @moduledoc """
  Defines the runtime configuration for the proxy.
  """
  require Logger

  defmodule Item do
    @enforce_keys [:identifier, :target_url, :ttl]
    defstruct [:identifier, :target_url, :ttl]
  end

  defmodule Fetcher do
    @moduledoc """
    A behaviour + shared methods for config fetching.
    """
    @callback fetch_config!() :: list(Item)

    def convert_yaml_to_config_items(body) do
      YamlElixir.read_from_string!(body)
      |> Map.fetch!("feeds")
      |> Enum.map(fn f ->
        %Item{
          identifier: Map.fetch!(f, "unique_slug"),
          target_url: Map.fetch!(f, "url"),
          # By default, no TTL
          ttl: Map.get(f, "ttl", 0)
        }
      end)
    end

    # for easy access, we're indexing items by identifier
    # caveat: this will raise if more than 2 items share
    # the same slug/identifier
    def index_items_by_unique_identifier(items) do
      items
      |> Enum.group_by(& &1.identifier)
      |> Enum.map(fn {k, [v]} -> {k, v} end)
      |> Enum.into(%{})
    end
  end

  defmodule GitHub do
    @behaviour Fetcher

    @doc """
    Fetch the configuration from GitHub and cache it in RAM using Cachex.

    This will allow expiry via a simple key deletion.
    """
    @impl Fetcher
    def fetch_config!() do
      # NOTE: this won't handle errors correctly at this point
      fetch_config = fn _key -> {:commit, fetch_config_no_cache!()} end
      case {_operation, _result} = Cachex.fetch(Unlock.Cachex, "config:proxy", fetch_config) do
        {:commit, result} ->
          result
        {:ok, result} ->
          result
      end
    end

    @doc """
    Retrieve the configuration from GitHub as a map.
    """
    def fetch_config_no_cache!() do
      fetch_config_from_github!()
      |> Fetcher.convert_yaml_to_config_items()
      |> Fetcher.index_items_by_unique_identifier()
    end

    defp fetch_config_from_github!() do
      Logger.info("Fetching proxy config from GitHub")
      config_url = Application.fetch_env!(:unlock, :github_config_url)
      github_token = Application.fetch_env!(:unlock, :github_auth_token)

      %{status: 200, body: body} =
        Unlock.HTTP.Client.impl().get!(config_url, [{"Authorization", "token #{github_token}"}])

      body
    end
  end
end
