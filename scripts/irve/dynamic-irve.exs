my_app_root = Path.join(__DIR__, "../..")

# hybrid setup to rely on the whole app setup but increment with a specificy dependency
Mix.install(
  [
    {:my_app, path: my_app_root, env: :dev},
    {:io_ansi_table, "~> 1.0"}
  ],
  config_path: Path.join(my_app_root, "config/config.exs"),
  lockfile: Path.join(my_app_root, "mix.lock")
)

params = %{
  page: 1,
  page_size: 500,
  schema: "etalab/schema-irve-dynamique"
}

url = "https://www.data.gouv.fr/api/1/datasets/?#{URI.encode_query(params)}"

defmodule Query do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  def cached_get!(url, options \\ []) do
    Transport.HTTPClient.get!(url,
      decode_body: options |> Keyword.get(:decode_body, true),
      custom_cache_dir: cache_dir(),
      enable_cache: true
    )
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
      r
      |> Map.put("dataset_url", dataset["page"])
      |> Map.put("organization", dataset["organization"]["name"])
    end)
  end)
  |> Enum.reject(fn r ->
    # https://www.data.gouv.fr/en/datasets/exemple-jeu-de-donnees-points-de-recharge-de-xxxxxx-donnees-statiques-et-dynamiques/
    # a fake dataset with non existent url donnesdynamiquesIRVE.fr
    r["id"] == "5ef6ddff-2f98-4300-9e6e-1b47ea4ab779"
  end)

defmodule IRVECheck do
  def get_body(url) do
    # control the decoding ourselves ; by default Req would decode via CSV itself
    %{status: 200, body: body} = Query.cached_get!(url, decode_body: false)
    body
  end

  def get_headers(url) do
    [get_body(url)]
    # quick first decode to get the headers, even if the file has no rows
    |> CSV.decode!(headers: false)
    |> Enum.take(1)
    |> List.first()
  end

  def is_dynamic_irve?(url) do
    headers = url |> get_headers()

    "id_pdc_itinerance" in headers && "etat_pdc" in headers
  end

  def rows_in_file(url) do
    [get_body(url)]
    |> CSV.decode!(headers: true)
    |> Enum.to_list()
    |> length()
  end

  def time_window(url) do
    data =
      [get_body(url)]
      |> CSV.decode!(headers: true)
      |> Enum.map(fn x -> (x["horodatage"] || "???") |> String.slice(0, 10) end)
      |> Enum.to_list()
      |> Enum.sort()

    {List.first(data), List.last(data), Enum.count(data)}
  end
end

IO.puts("========== #{resources |> length()} candidates ==========\n\n")

rows =
  resources
  |> Enum.map(fn r ->
    %{
      dataset_url: r["dataset_url"],
      organization: r["organization"],
      resource_url: r["url"],
      dynamic_irve_likely: IRVECheck.is_dynamic_irve?(r["url"]),
      time_window: IRVECheck.time_window(r["url"]),
      rows_in_file: IRVECheck.rows_in_file(r["url"])
    }
  end)

IO.inspect(rows, IEx.inspect_opts())

IO.ANSI.Table.start([:organization, :dynamic_irve_likely, :rows_in_file, :dataset_url],
  sort_specs: [desc: :rows_in_file]
)

IO.ANSI.Table.format(rows)

# TODO: improve speed for iterative work
# TODO: list validation and validation date
