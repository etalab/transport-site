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
  def pages(base_url, pagination_options \\ []) do
    http_client = Transport.HTTPClient
    options = http_options()

    Transport.IRVE.HTTPPagination.naive_paginated_urls_stream(base_url, http_client, options, pagination_options)
  end

  # Unused now, we don’t keep in RAM the body of resources when downloading them.
  def get!(url, options \\ []) do
    http_client = Transport.HTTPClient
    options = options |> Keyword.merge(http_options())

    http_client.get!(url, options)
  end

  @doc """
  Downloads a file and stores in the temp folder, returns the stream to read it.
  This doesn’t use options |> Keyword.merge(http_options())
  Because the :into option of Req is incompatible with the custom caching mechanism.

  Use like this:
  resource = Transport.IRVE.Extractor.datagouv_resources() |> List.last
  stream = Transport.IRVE.Fetcher.get_and_store_file!(resource.url, resource.resource_title)
  stream.body |> Stream.each(&IO.puts/1) |> Stream.run()
  """
  def get_and_store_file!(url, file_name, options \\ []) do
    http_client = Transport.HTTPClient

    destination = File.stream!(System.tmp_dir!() |> Path.join(file_name))

    options = options |> Keyword.put(:into, destination)

    http_client.get!(url, options)
  end
end
