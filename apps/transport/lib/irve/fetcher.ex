defmodule Transport.IRVE.Fetcher do
  @moduledoc """
  A central point for HTTP fetching, including:
  - data gouv pagination
  - individual resource fetching
  """

  # the root phoenix path, to be improved of course
  def cache_dir, do: Path.join(__ENV__.file, "../../../../../cache-dir") |> Path.expand()

  def http_options do
    # NOTE: useful when iterating in development, disabled by default
    if Application.get_env(:transport, :irve_consolidation_caching, false) do
      [
        enable_cache: true,
        custom_cache_dir: cache_dir()
      ]
    else
      [
        enable_cache: false
      ]
    end
  end

  @doc """
  Return the list of all pages for a given query (by querying one page and inferring other pages).
  """
  def pages(base_url) do
    http_client = Transport.HTTPClient
    base_url = URI.encode(base_url)
    options = http_options()

    Transport.IRVE.HTTPPagination.naive_paginated_urls_stream(base_url, http_client, options)
  end

  def get!(url, options \\ []) do
    http_client = Transport.HTTPClient
    url = URI.encode(url)
    options = options |> Keyword.merge(http_options())

    http_client.get!(url, options)
  end
end
