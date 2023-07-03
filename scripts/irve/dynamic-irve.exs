Mix.install([
  {:req, "~> 0.3.9"},
  {:jason, "~> 1.4"},
  {:csv, "~> 3.0"}
])

Code.require_file(__DIR__ <> "/req_custom_cache.exs")

params = %{
  page: 1,
  page_size: 500,
  schema: "etalab/schema-irve-dynamique"
}

url = "https://www.data.gouv.fr/api/1/datasets/?#{URI.encode_query(params)}"

defmodule Query do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  def cached_get!(url) do
    req = Req.new() |> CustomCache.attach()
    Req.get!(req, url: url, custom_cache_dir: cache_dir())
  end
end

%{status: 200, body: datasets} = Query.cached_get!(url)

# ensure there is only one page + grab the data
unless is_nil(datasets["next_page"]), do: raise("should not have next page")

resources =
  datasets["data"]
  |> Enum.flat_map(fn dataset ->
    # IO.inspect(dataset, IEx.inspect_opts())

    dataset["resources"]
    |> Enum.filter(fn r -> r["schema"]["name"] == "etalab/schema-irve-dynamique" end)
    |> Enum.map(fn r ->
      Map.put(r, "dataset_url", dataset["page"])
    end)
  end)
  |> Enum.reject(fn r ->
    # https://www.data.gouv.fr/en/datasets/exemple-jeu-de-donnees-points-de-recharge-de-xxxxxx-donnees-statiques-et-dynamiques/
    # a fake dataset with non existent url donnesdynamiquesIRVE.fr
    r["id"] == "5ef6ddff-2f98-4300-9e6e-1b47ea4ab779"
  end)

# IO.inspect resources |> Enum.map &(&1["url"])

defmodule IRVECheck do
  def is_dynamic_irve?(url) do
    %{status: 200, body: body} = Query.cached_get!(url)

    # quick first decode to get the headers, even if the file has no rows
    data =
      [body]
      |> CSV.decode!(headers: false)
      |> Enum.take(1)
      |> List.first()

    "id_pdc_itinerance" in data && "etat_pdc" in data
  end

  def time_window(url) do
    %{status: 200, body: body} = Query.cached_get!(url)

    data =
      [body]
      |> CSV.decode!(headers: true)
      |> Enum.map(fn x -> (x["horodatage"] || "???") |> String.slice(0, 10) end)
      |> Enum.to_list()
      |> Enum.sort()

    {List.first(data), List.last(data)}
  end
end

resources
|> Enum.each(fn r ->
  IO.puts("\n" <> r["dataset_url"])

  IO.puts(
    r["url"] <>
      " --- " <>
      if(IRVECheck.is_dynamic_irve?(r["url"]), do: "OK", else: "KO") <>
      " " <> (IRVECheck.time_window(r["url"]) |> inspect)
  )
end)
