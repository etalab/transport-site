defmodule Transport do
  defmodule HTTPPagination do
    @doc """
    Using a base url and an http client, generates a stream of pages urls using
    a naive algorithm to build all urls upfront instead of having to wait for each
    page before getting the other pages.

    This will only work for some cases (e.g. datagouv).

    Current implementation assumes fixed field names and a decoded (JSON, typically) response,
    but is already partially generic.
    """
    def naive_paginated_urls_stream(base_url, http_client, http_client_options) do
      # NOTE: could be made customisable
      page_size = 100
      %{status: 200, body: data} = http_client.get!(url = base_url <> "&page_size=#{page_size}", http_client_options)

      # NOTE: using pattern matching to warn about "silent limitations" on the page_size from e.g. datagouv
      # This prevents from highly problematic holes in the sequence of data, if the remote server truncates
      # the page_size without giving any error.
      %{"total" => total, "page_size" => ^page_size} = data
      nb_pages = div(total, page_size) + 1

      IO.puts("Processing #{url} (pages: #{nb_pages})")

      # NOTE: contract may change for something more flexible
      1..nb_pages
      |> Stream.map(&%{url: base_url <> "&page=#{&1}&page_size=#{page_size}", source: base_url})
    end
  end
end
