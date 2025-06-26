defmodule Transport.IRVE.HTTPPagination do
  @moduledoc """
  Although namespaced under IRVE for simplicity, this is more data-gouv specific.

  This provides a paginating strategy based on the idea of generating all paginated
  urls at once, based on the first page response, instead of waiting for each link.

  Works at the moment, could need more work if data gouv changes of behaviour
  in the future though.
  """

  require Logger

  @doc """
  Using a base url and an http client, generates a stream of pages urls using
  a naive algorithm to build all urls upfront instead of having to wait for each
  page before getting the other pages.

  This will only work for some cases (e.g. datagouv).

  Current implementation assumes fixed field names and a decoded (JSON, typically) response,
  but is already partially generic.
  """
  def naive_paginated_urls_stream(base_url, http_client, http_client_options, pagination_options \\ []) do
    page_size = pagination_options |> Keyword.get(:page_size, 100)

    %Req.Response{status: 200, body: data} =
      http_client.get!(url = base_url <> "&page_size=#{page_size}", http_client_options)

    # NOTE: using pattern matching to warn about "silent limitations" on the page_size from e.g. datagouv
    # This prevents from highly problematic holes in the sequence of data, if the remote server truncates
    # the page_size without giving any error.
    %{"total" => total, "page_size" => ^page_size} = data
    nb_pages = num_pages(total_items: total, items_per_page: page_size)

    Logger.info("Generating paginated urls from #{url} (pages: #{nb_pages})")

    # NOTE: contract may change for something more flexible
    1..nb_pages
    |> Stream.map(&%{url: base_url <> "&page=#{&1}&page_size=#{page_size}", source: base_url})
  end

  @doc """
  Compute the number of pages based on total items count and page size.

  Context: if we request one page too much on data gouv, an error 404 is raised (at time of writing), so
  we want to protect against this.

  Let's test a few edge cases (one of them led to a failure causing me to write this).

  In case we have no items, we also have no pages at all:

      iex> num_pages(total_items: 0, items_per_page: 10)
      0

  If we have just one item, we get one single page:

      iex> num_pages(total_items: 1, items_per_page: 10)
      1

  Also, if the page is full, we don't overflow:

      iex> num_pages(total_items: 10, items_per_page: 10)
      1

  And the next page flows right after:

      iex> num_pages(total_items: 11, items_per_page: 10)
      2

  Finally (real-life case), if we get a number of fully filled pages, we must get it right:

      iex> num_pages(total_items: 1200, items_per_page: 100)
      12
  """
  def num_pages(total_items: 0, items_per_page: _), do: 0
  def num_pages(total_items: total_items, items_per_page: items_per_page), do: div(total_items - 1, items_per_page) + 1
end
