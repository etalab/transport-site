defmodule Unlock.Config do
  @moduledoc """
  Defines the runtime configuration for the proxy.
  """
  require Logger

  defmodule Item.Generic.HTTP do
    @moduledoc """
    An intermediate structure to add a bit of typing to the
    external YAML configuration, for generic HTTP and gtfs-rt items.

    It supports hardcoded request headers for e.g. simple authentication.

    Default subtype is "gtfs-rt" for historical reasons, see `convert_yaml_item_to_struct` in the code.
    """
    @enforce_keys [:identifier, :target_url, :ttl]
    defstruct [
      :identifier,
      :slug,
      :target_url,
      :ttl,
      subtype: "gtfs-rt",
      request_headers: [],
      response_headers: []
    ]
  end

  defmodule Item.SIRI do
    @moduledoc """
    Intermediate structure for SIRI configured items.
    """
    @enforce_keys [:identifier, :target_url, :requestor_ref]

    @type t :: %__MODULE__{identifier: binary(), target_url: binary(), requestor_ref: binary(), request_headers: list()}
    defstruct [:identifier, :target_url, :requestor_ref, request_headers: []]
  end

  defmodule Item.Aggregate do
    @moduledoc """
    Intermediate structure for aggregated configured items.

    Feeds (sub-items) are strongly typed
    """
    @enforce_keys [:identifier, :feeds]

    defstruct [:identifier, :feeds, :ttl]
  end

  defmodule Item.S3 do
    @moduledoc """
    Intermediate structure for S3-based configured items.
    """

    @enforce_keys [:identifier, :bucket, :path, :ttl]
    defstruct [:identifier, :bucket, :path, :ttl]
  end

  defmodule Item.GBFS do
    @moduledoc """
    Intermediate structure for GBFS configured feeds.
    """
    @enforce_keys [:identifier, :base_url, :ttl]
    defstruct [
      :identifier,
      :base_url,
      :endpoint,
      :ttl,
      request_headers: [],
      response_headers: []
    ]
  end

  defmodule Fetcher do
    @moduledoc """
    A behaviour + shared methods for config fetching.
    """
    @callback fetch_config!() :: list(Item)
    @callback clear_config_cache!() :: any

    def convert_aggregate_sub_item(sub_item) do
      sub_item
      # Default to generic-http (typically used for IRVE)
      |> Map.put_new("type", "generic-http")
      # Use a default 10-second TTL for sub-feeds, unless specified in the config
      |> Map.put_new("ttl", 10)
      |> convert_yaml_item_to_struct()
    end

    def convert_yaml_item_to_struct(%{"type" => "aggregate"} = item) do
      %Item.Aggregate{
        identifier: Map.fetch!(item, "identifier"),
        # NOTE: ultimately a map (key = identifier) would be better than an array here,
        # but that will do for now as the number of items is low
        feeds: item |> Map.fetch!("feeds") |> Enum.map(&convert_aggregate_sub_item(&1)),
        ttl: Map.get(item, "ttl", 10)
      }
    end

    def convert_yaml_item_to_struct(%{"type" => "siri"} = item) do
      %Item.SIRI{
        identifier: Map.fetch!(item, "identifier"),
        target_url: Map.fetch!(item, "target_url"),
        requestor_ref: Map.fetch!(item, "requestor_ref"),
        request_headers: parse_config_http_headers(Map.get(item, "request_headers", []))
      }
    end

    @doc """
    At the moment, GTFS-RT is just an alias for HTTP generic. This is done
    to make it easier to achieve alternate processing later if needed.
    """
    def convert_yaml_item_to_struct(%{"type" => subtype} = item) when subtype in ["generic-http", "gtfs-rt"] do
      %Item.Generic.HTTP{
        identifier: Map.fetch!(item, "identifier"),
        slug: Map.get(item, "slug"),
        target_url: Map.fetch!(item, "target_url"),
        # By default, no TTL
        ttl: Map.get(item, "ttl", 0),
        # keep the subtype in case we need to do alternate processing later, without creating too many types too soon
        subtype: subtype,
        request_headers: parse_config_http_headers(Map.get(item, "request_headers", [])),
        response_headers: parse_config_http_headers(Map.get(item, "response_headers", []))
      }
    end

    def convert_yaml_item_to_struct(%{"type" => "gbfs"} = item) do
      %Item.GBFS{
        identifier: Map.fetch!(item, "identifier"),
        base_url: Map.fetch!(item, "base_url"),
        # By default, no TTL
        ttl: Map.get(item, "ttl", 0),
        request_headers: parse_config_http_headers(Map.get(item, "request_headers", [])),
        response_headers: parse_config_http_headers(Map.get(item, "response_headers", []))
      }
    end

    def convert_yaml_item_to_struct(%{"type" => "s3"} = item) do
      %Item.S3{
        identifier: Map.fetch!(item, "identifier"),
        bucket: Map.fetch!(item, "bucket"),
        path: Map.fetch!(item, "path"),
        ttl: Map.get(item, "ttl", 10)
      }
    end

    # provide an automatic upgrade path for existing configuration, to be
    # deprecated later
    def convert_yaml_item_to_struct(item) when not is_map_key(item, "type") do
      convert_yaml_item_to_struct(Map.put(item, "type", "gtfs-rt"))
    end

    def convert_yaml_to_config_items(body) do
      body
      |> YamlElixir.read_from_string!()
      |> Map.fetch!("feeds")
      |> Enum.map(&convert_yaml_item_to_struct(&1))
    end

    @doc """
    In the YAML, we use an array of 2-element arrays to specify optional hardcoded request headers.
    This method converts that to a list of tuple, commonly used for HTTP headers
    (e.g. `Mint.Types.headers()` in https://github.com/elixir-mint/mint/blob/main/lib/mint/types.ex)
    """
    def parse_config_http_headers(list) do
      list
      |> Enum.map(fn [k, v] -> {k, v} end)
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
    import Unlock.Shared, only: [cache_name: 0]
    @behaviour Fetcher

    @proxy_config_cache_key "config:proxy"

    @moduledoc """
    Fetch the configuration from GitHub and cache it in RAM using Cachex.

    This will allow expiry via a simple key deletion.
    """
    @impl Fetcher
    def fetch_config! do
      # NOTE: this won't handle errors correctly at this point
      fetch_config = fn _key -> {:commit, fetch_config_no_cache!()} end

      case {_operation, _result} = Cachex.fetch(cache_name(), @proxy_config_cache_key, fetch_config) do
        {:commit, result} ->
          Cachex.persist(cache_name(), @proxy_config_cache_key)
          result

        {:ok, result} ->
          result
      end
    end

    @impl Fetcher
    def clear_config_cache! do
      Cachex.del!(cache_name(), @proxy_config_cache_key)
    end

    @doc """
    Retrieve the configuration from GitHub as a map.
    """
    def fetch_config_no_cache! do
      fetch_config_from_github!()
      |> Fetcher.convert_yaml_to_config_items()
      |> Fetcher.index_items_by_unique_identifier()
    end

    defp fetch_config_from_github! do
      Logger.info("Fetching proxy config from GitHub")
      config_url = Application.fetch_env!(:transport, :unlock_github_config_url)
      github_token = Application.fetch_env!(:transport, :unlock_github_auth_token)

      %{status: 200, body: body} =
        Unlock.HTTP.Client.impl().get!(config_url, [{"Authorization", "token #{github_token}"}], [])

      body
    end
  end

  defmodule Disk do
    @behaviour Fetcher
    require Logger

    @moduledoc """
    Fetch the configuration from a file on disk (useful for development or disk-based persistence).
    """
    @impl Fetcher
    def fetch_config! do
      config_file = Application.fetch_env!(:transport, :unlock_disk_config_file)

      config_file
      |> File.read!()
      |> Fetcher.convert_yaml_to_config_items()
      |> Fetcher.index_items_by_unique_identifier()
    end

    @impl Fetcher
    def clear_config_cache! do
      Logger.info("Clearing cache config (no-op)")
    end
  end
end
