# the basis of a mass-analysis script for IRVE files,
# inspired by https://github.com/etalab/notebooks/blob/master/irve-v2/consolidation-irve-v2.ipynb

Mix.install([
  {:req, "~> 0.3.0"}
])

Code.require_file(Path.join(__ENV__.file, "../req_custom_cache.exs"))

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
    page_size = 100
    data = get!(url = base_url <> "&page_size=#{page_size}")

    # NOTE: using pattern matching to warn me about "silent limitations" on the page_size from data gouv
    %{"total" => total, "page_size" => ^page_size} = data
    nb_pages = div(total, page_size) + 1

    IO.puts "Processing #{url} (pages: #{nb_pages})"

    1..nb_pages
    |> Stream.map(&%{url: base_url <> "&page=#{&1}&page_size=#{page_size}", source: base_url})
  end
end

defmodule Helper do
  # or: fn(i) -> i end
  # or: &Function.identity/1
  def inspect(stream, f \\ &(&1)) do
    Stream.each(stream, fn(x) ->
      IO.inspect(f.(x), IEx.inspect_opts)
    end)
  end
end
# NOTE: currently not deduping, because I saw weird things while doing it

# TODO: once done, also check the other sources (catch with a wider net).
# But do not get lost in the process, so focus first on the "real thing".
resources = [
#  "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve",
  "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique",
  # "https://www.data.gouv.fr/api/1/datasets/?tag=irve",
  # "https://www.data.gouv.fr/api/1/datasets/?q=irve",
  # "https://www.data.gouv.fr/api/1/datasets/?q=recharge+véhicules+électriques",
]
|> Enum.map(&Streamer.pages(&1))
|> Stream.concat()
|> Stream.map(fn %{url: url} = page -> Map.put(page, :data, Streamer.get!(url)) end)
# |> Helper.inspect(fn(x) ->
#   Map.take(x[:data], ["page", "page_size", "total"])
# end)
|> Stream.flat_map(fn page -> page[:data]["data"] end)
|> Stream.map(fn dataset ->
  dataset["resources"]
end)
|> Stream.concat()
|> Stream.map(fn(x) ->
  %{
    id: get_in(x, ["id"]),
    last_modified: get_in(x, ["last_modified"]),
    valid: get_in(x, ["extras", "validation-report:valid_resource"]),
    validation_date: get_in(x, ["extras", "validation-report:validation_date"]),
    schema_name: get_in(x, ["schema", "name"]),
    schema_version: get_in(x, ["schema", "version"]),
  }
end)
|> Stream.filter(fn(x) -> x[:schema_name] == "etalab/schema-irve-statique" end)
|> Enum.into([])

# TODO: show as tabular view (more compact)
IO.puts "=== Sample ==="
resources |> Enum.take(2) |> IO.inspect(IEx.inspect_opts)

IO.puts "=== Stats ==="
IO.inspect(%{count: resources |> length}, IEx.inspect_opts |> Keyword.put(:label, "total_count"))

# M'a aidé à me rendre compte que.. un gros paquet est invalide!
resources
|> Enum.frequencies_by(fn(x) -> x[:valid] end)
|> IO.inspect(IEx.inspect_opts |> Keyword.put(:label, "group_by(:valid)"))

# M'a aidé à me rendre compte que... il y avait plusieurs schémas, car on recherche par "dataset",
# mais après on travaille au niveau ressources, et donc on cherche par le "schéma de chaque ressource du dataset",
# ce qui fait qu'il y a des choses en trop.
resources
|> Enum.frequencies_by(fn(x) -> x[:schema_name] end)
|> IO.inspect(IEx.inspect_opts |> Keyword.put(:label, "group_by(:schema_name)"))

resources
|> Enum.frequencies_by(fn(x) -> x[:schema_version] end)
|> IO.inspect(IEx.inspect_opts |> Keyword.put(:label, "group_by(:schema_version)"))

# Combien ça donne, en pourcentage ? (facile via dataframe si dispo?)
# Combien par "date de validation" breakdown ?
# Combien par "date de mise à jour" (théorique ???)
# Combien de PDC ça constitue ?
# Tout télécharger ?
# Tout revalider moi-même et vérifier ? Oui. Oui. On aura des surprises.
