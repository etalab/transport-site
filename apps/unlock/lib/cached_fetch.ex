defmodule Unlock.CachedFetch do
  @moduledoc """
  A place centralizing Cachex-compatible HTTP calls.
  """

  require Logger

  # We put a hard limit on what can be cached, and otherwise will just
  # send back without caching. This means the remote server is less protected
  # temporarily, but also that we do not blow up our whole architecture due to
  # RAM consumption
  @max_allowed_cached_byte_size 20 * 1024 * 1024

  # defaults
  def fetch_data(_item, _http_client_options \\ [])

  def fetch_data(%Unlock.Config.Item.Generic.HTTP{} = item, http_client_options) do
    response = Unlock.HTTP.Client.impl().get!(item.target_url, item.request_headers, http_client_options)
    size = byte_size(response.body)

    if size > @max_allowed_cached_byte_size do
      Logger.warning("Payload is too large (#{size} bytes > #{@max_allowed_cached_byte_size}). Skipping cache.")
      {:ignore, response}
    else
      {:commit, response, ttl: :timer.seconds(item.ttl)}
    end
  end

  # For S3 hosted files (which we control), which are currently larger, go a bit further
  @max_allowed_s3_cached_byte_size 4 * 20 * 1024 * 1024

  def fetch_data(%Unlock.Config.Item.S3{} = item, _http_client_options) do
    bucket = item.bucket |> String.to_existing_atom()
    path = item.path

    response = Transport.S3.get_object!(bucket, path)
    size = byte_size(response.body)

    if size > @max_allowed_s3_cached_byte_size do
      Logger.warning("S3 Payload is too large (#{size} bytes > #{@max_allowed_s3_cached_byte_size}). Skipping cache.")
      {:ignore, response}
    else
      {:commit, response, ttl: :timer.seconds(item.ttl)}
    end
  end
end
