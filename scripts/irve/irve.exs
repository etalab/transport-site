# the basis of a mass-analysis script for IRVE files,
# inspired by https://github.com/etalab/notebooks/blob/master/irve-v2/consolidation-irve-v2.ipynb

Mix.install([
  {:req, "~> 0.3.0"}
])

Code.require_file("req_custom_cache.exs")

defmodule Streamer do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  @doc """
  Execute HTTP query, unless the file is already in the disk cache.
  """
  def get!(url) do
    url = URI.encode(url)
    # use the cache plugin
    req = Req.new() |> CustomCache.attach()
    %{body: body, status: 200} = Req.get!(req, url: url, custom_cache_dir: cache_dir())
    body
  end

  @doc """
  Query one page, and use that to infer the list of all urls (for index-based pagination like data gouv)
  """
  def pages(base_url) do
    data = get!(base_url <> "&page_size=100")
    %{"total" => total, "page_size" => page_size} = data
    nb_pages = div(total, page_size) + 1

    1..nb_pages
    |> Stream.map(&%{url: base_url <> "&page=#{&1}", source: base_url})
  end
end

# NOTE: currently not deduping, because I saw weird things while doing it
[
  "https://www.data.gouv.fr/api/1/datasets/?tag=irve",
  "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve",
  "https://www.data.gouv.fr/api/1/datasets/?q=recharge+véhicules+électriques",
  "https://www.data.gouv.fr/api/1/datasets/?q=irve"
]
|> Enum.map(&Streamer.pages(&1))
|> Stream.concat()
|> Stream.map(fn %{url: url} = page -> Map.put(page, :data, Streamer.get!(url)) end)
|> Stream.flat_map(fn page -> page[:data]["data"] end)
|> Stream.map(fn dataset ->
  for resource <- dataset["resources"] do
    %{
      dataset_id: Map.fetch!(dataset, "id"),
      dataset_slug: Map.fetch!(dataset, "slug"),
      dataset_page: Map.fetch!(dataset, "page"),
      resource_id: Map.fetch!(resource, "id"),
      resource_title: Map.fetch!(resource, "title"),
      resource_last_modified: Map.fetch!(resource, "last_modified")
    }
  end
end)
|> Stream.concat()
|> Stream.each(fn x -> IO.inspect(x, IEx.inspect_opts()) end)
|> Stream.run()
