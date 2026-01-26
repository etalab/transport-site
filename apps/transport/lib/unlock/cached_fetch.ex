defmodule Unlock.CachedFetch do
  @moduledoc """
  `Cachex` is used for caching. It expects caching callbacks to
  return tuples such as `{:ignore, resp}`, `{:commit, resp, expire: xyz}` etc
  to understand what we want it to do for us.

  This module `CachedFetch` groups the fetching logic for two types of items where
  it makes sense:
  - `%Unlock.Config.Item.Generic.HTTP{}`
  - `%Unlock.Config.Item.S3{}`

  The response part of the tuple is standardized by us to `%Unlock.HTTP.Response{}` structures,
  which are then serialized into RAM by `Cachex`.
  """

  require Logger

  # We put a hard limit on what can be cached, and otherwise will just
  # send back without caching. This means the remote server is less protected
  # temporarily, but also that we do not blow up our whole architecture due to
  # RAM consumption
  @max_allowed_cached_byte_size 20 * 1024 * 1024

  # defaults
  def fetch_data(_item, _http_client_options \\ [])

  def fetch_data(%Unlock.Config.Item.Generic.HTTP{caching: "disk"} = item, _http_client_options) do
    path = disk_path(item)
    response = Unlock.HTTP.Client.impl().stream!(item.target_url, item.request_headers, path)
    {:commit, %{response | body: path}, expire: :timer.seconds(item.ttl)}
  end

  def fetch_data(%Unlock.Config.Item.Generic.HTTP{} = item, http_client_options) do
    response = Unlock.HTTP.Client.impl().get!(item.target_url, item.request_headers, http_client_options)
    size = byte_size(response.body)

    if size > @max_allowed_cached_byte_size do
      Logger.warning("Payload is too large (#{size} bytes > #{@max_allowed_cached_byte_size}). Skipping cache.")
      {:ignore, response}
    else
      {:commit, response, expire: :timer.seconds(item.ttl)}
    end
  end

  def fetch_data(%Unlock.Config.Item.GBFS{} = item, http_client_options) do
    target_url = item.base_url |> String.replace("gbfs.json", item.endpoint)
    response = Unlock.HTTP.Client.impl().get!(target_url, item.request_headers, http_client_options)
    size = byte_size(response.body)

    if size > @max_allowed_cached_byte_size do
      Logger.warning("Payload is too large (#{size} bytes > #{@max_allowed_cached_byte_size}). Skipping cache.")
      {:ignore, response}
    else
      {:commit, response, expire: :timer.seconds(item.ttl)}
    end
  end

  def fetch_data(%Unlock.Config.Item.S3{} = item, _http_client_options) do
    bucket = item.bucket |> String.to_existing_atom()
    path = item.path
    destination_path = disk_path(item)

    # Verify if the response cached is still valid by comparing ETags
    etag_cache_key = Unlock.Shared.cache_key(item.identifier, "etag")
    cached_reponse = Cachex.get(Unlock.Shared.cache_name(), etag_cache_key)

    etag =
      case cached_reponse do
        {:ok, %Unlock.HTTP.Response{headers: headers}} -> etag_value(headers)
        _ -> nil
      end

    %{headers: headers, status_code: status_code} = Transport.S3.head_object!(bucket, path)
    object_etag = etag_value(headers)

    # ETags are still the same, keep the cached response (and file) for the TTL duration
    if not is_nil(object_etag) and object_etag == etag do
      {:ok, response} = cached_reponse
      {:commit, response, expire: :timer.seconds(item.ttl)}
      # File changed or cache expired: download the file to disk again
    else
      Transport.S3.download_file!(bucket, path, destination_path)
      response = %Unlock.HTTP.Response{body: destination_path, status: status_code, headers: headers}
      # Save a cache key without an expire, to check again the cache
      Cachex.put(Unlock.Shared.cache_name(), etag_cache_key, response)
      {:commit, response, expire: :timer.seconds(item.ttl)}
    end
  end

  defp disk_path(item) do
    System.tmp_dir!() |> Path.join("unlock_disk_cache:" <> item.identifier)
  end

  defp etag_value(headers) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(k) == "etag", do: v end)
  end
end
