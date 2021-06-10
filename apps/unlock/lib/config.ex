defmodule Unlock.Config do
  @moduledoc """
  Defines the runtime configuration for the proxy.
  """
  require Logger

  @callback fetch_config!() :: any

  @doc """
  Fetch the configuration from GitHub and cache it in RAM using Cachex.

  This will allow expiry via a simple key deletion.
  """
  def fetch_config!() do
    # NOTE: this won't handle errors correctly
    fetch_config = fn _key -> {:commit, fetch_config_no_cache!()} end
    cache_name = Unlock.Cachex
    cache_key = "config:proxy"
    # NOTE: we do not want any expiry here. For now I'm using a very large TTL
    ttl = :timer.hours(100_000)

    case {_operation, _result} = Cachex.fetch(cache_name, cache_key, fetch_config) do
      {:commit, result} ->
        Cachex.expire(cache_name, cache_key, ttl)
        result
      {:ok, result} ->
        result
    end
  end

  @doc """
  Retrieve the configuration from GitHub as a map.
  """
  def fetch_config_no_cache!() do
    Logger.info "Fetching proxy config from GitHub"
    # NOTE: this stuff will have to move into the config
    url = "https://raw.githubusercontent.com/etalab/transport-proxy-config/master/proxy-config.yml"
    github_token = System.fetch_env!("TRANSPORT_PROXY_CONFIG_GITHUB_TOKEN")

    {:ok, _response = %{status: 200, body: body}} = Finch.build(:get, url, [{"Authorization", "token #{github_token}"}]) |> Finch.request(Unlock.Finch)

    YamlElixir.read_from_string!(body)
    |> Map.fetch!("feeds")
    |> Enum.group_by(fn(x) -> x["unique_slug"] end)
  end
end
