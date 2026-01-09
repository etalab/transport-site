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

  def fetch_data(%Unlock.Config.Item.Generic.HTTP{caching: "disk"} = item, http_client_options) do
    path = System.tmp_dir!() |> Path.join(item.identifier)
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

  # For S3 hosted files (which we control), which are currently larger, go a bit further
  @max_allowed_s3_cached_byte_size 4 * 20 * 1024 * 1024

  def fetch_data(%Unlock.Config.Item.S3{} = item, _http_client_options) do
    bucket = item.bucket |> String.to_existing_atom()
    path = item.path

    response = Transport.S3.get_object!(bucket, path)

    # create the same type of structure as `fetch_data(%Generic.HTTP{})` calls. See `http_client.ex`.
    response = %Unlock.HTTP.Response{body: response.body, status: response.status_code, headers: []}
    size = byte_size(response.body)

    if size > @max_allowed_s3_cached_byte_size do
      Logger.warning("S3 Payload is too large (#{size} bytes > #{@max_allowed_s3_cached_byte_size}). Skipping cache.")
      {:ignore, response}
    else
      {:commit, response, expire: :timer.seconds(item.ttl)}
    end
  end
end
