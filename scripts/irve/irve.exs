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
  def get!(url, options \\ []) do
    url = URI.encode(url)
    # use the cache plugin
    req = Req.new() |> CustomCache.attach()
    %{body: body, status: 200} = Req.get!(req, options |> Keyword.merge(url: url, custom_cache_dir: cache_dir()))
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

    IO.puts("Processing #{url} (pages: #{nb_pages})")

    1..nb_pages
    |> Stream.map(&%{url: base_url <> "&page=#{&1}&page_size=#{page_size}", source: base_url})
  end
end

defmodule Helper do
  # or: fn(i) -> i end
  # or: &Function.identity/1
  def inspect(stream, f \\ & &1) do
    Stream.each(stream, fn x ->
      IO.inspect(f.(x), IEx.inspect_opts())
    end)
  end
end

# NOTE: currently not deduping, because I saw weird things while doing it

# TODO: once done, also check the other sources (catch with a wider net).
# But do not get lost in the process, so focus first on the "real thing".
resources =
  [
    #  "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve",
    "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique"
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
    |> Enum.map(fn x -> Map.put(x, :dataset_id, dataset["id"]) end)
  end)
  |> Stream.concat()
  # |> Stream.take(1)
  # |> Helper.inspect()
  |> Stream.map(fn x ->
    %{
      id: get_in(x, ["id"]),
      dataset_id: get_in(x, [:dataset_id]),
      last_modified: get_in(x, ["last_modified"]),
      valid: get_in(x, ["extras", "validation-report:valid_resource"]),
      validation_date: get_in(x, ["extras", "validation-report:validation_date"]),
      schema_name: get_in(x, ["schema", "name"]),
      schema_version: get_in(x, ["schema", "version"]),
      filetype: get_in(x, ["filetype"]),
      last_modified: get_in(x, ["last_modified"]),
      # vs latest?
      url: get_in(x, ["url"])
    }
  end)
  |> Stream.filter(fn x -> x[:schema_name] == "etalab/schema-irve-statique" end)
  |> Enum.into([])

# TODO: show as tabular view (more compact)
IO.puts("=== Sample ===")
resources |> Enum.take(2) |> IO.inspect(IEx.inspect_opts())

IO.puts("=== Stats ===")
IO.inspect(%{count: resources |> length}, IEx.inspect_opts() |> Keyword.put(:label, "total_count"))

# M'a aidé à me rendre compte que.. un gros paquet est invalide!
resources
|> Enum.frequencies_by(fn x -> x[:valid] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid)"))

# TODO: percent via dataframe if possible (simpler once we get used to it)
resources
|> Enum.frequencies_by(fn x -> x[:valid] end)
|> Enum.map(fn {a, v} -> ((100 * v / (resources |> length)) |> trunc() |> to_string) <> "%" end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid) as %"))

# M'a aidé à me rendre compte que... il y avait plusieurs schémas, car on recherche par "dataset",
# mais après on travaille au niveau ressources, et donc on cherche par le "schéma de chaque ressource du dataset",
# ce qui fait qu'il y a des choses en trop.
resources
|> Enum.frequencies_by(fn x -> x[:schema_name] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:schema_name)"))

resources
|> Enum.frequencies_by(fn x -> x[:schema_version] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:schema_version)"))

resources
|> Enum.frequencies_by(fn x -> x[:filetype] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:filetype)"))

resources =
  resources
  |> Enum.map(fn x ->
    body = Streamer.get!(x[:url], compressed: false, decode_body: false) |> String.split("\n")

    first_line =
      body
      |> hd()

    line_count = (body |> length) - 1

    id_detected = first_line |> String.contains?("id_pdc_itinerance")
    # a field from v1, which does not end like a field in v2
    old_schema = first_line |> String.contains?("ad_station")

    x
    |> Map.put(:id_pdc_itinerance_detected, id_detected)
    |> Map.put(:old_schema, old_schema)
    |> Map.put(:first_line, first_line)
    |> Map.put(:line_count, line_count)
  end)

resources
# |> Enum.filter(fn x -> x[:id_pdc_itinerance_detected] == true && x[:old_schema] == true end)
|> Enum.frequencies_by(fn x -> Map.take(x, [:id_pdc_itinerance_detected, :old_schema]) end)
|> IO.inspect()

# Format pourris ?
# Ancien schéma ? (en étant sûr)
# => Les invalides avec le bon format ?
# Tableau de pilotage
# invalides 2.2.0 ->

recent_stuff =
  resources
  |> Enum.filter(fn x -> x[:id_pdc_itinerance_detected] end)

recent_stuff
|> Enum.frequencies_by(fn x -> x[:valid] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid)"))

recent_stuff
|> Enum.filter(fn x -> x[:valid] != true end)
|> Enum.sort_by(fn x -> -x[:line_count] end)
|> Enum.map(fn x -> {x[:line_count], "https://www.data.gouv.fr/fr/datasets/" <> x[:dataset_id]} end)
|> IO.inspect(limit: :infinity)

# Combien par "date de validation" breakdown ?
# Combien par "date de mise à jour" (théorique ???)
# Combien de PDC ça constitue ?
# Tout revalider moi-même et vérifier ? Oui. Oui. On aura des surprises.
