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
    options = [
      decode_body: options |> Keyword.get(:decode_body, true),
      enable_cache: options |> Keyword.get(:enable_cache, false)
    ]

    options =
      if options[:enable_cache] do
        Keyword.merge(options, custom_cache_dir: cache_dir())
      else
        options
      end

    Transport.HTTPClient.get!(url, options)
  end
end

# disabling cache because one dataset is refreshed very frequently, caching leads to 404
%{status: 200, body: datasets} = Query.cached_get!(url, enable_cache: false)

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
      |> Map.put("valid", get_in(r, ["extras", "validation-report:valid_resource"]))
      |> Map.put("validation_date", get_in(r, ["extras", "validation-report:validation_date"]))
      |> Map.put("schema_name", get_in(r, ["schema", "name"]))
      |> Map.put("schema_version", get_in(r, ["schema", "version"]))
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

  def parse_csv(body) do
    [body]
    |> CSV.decode!(headers: true)
    |> Enum.to_list()
  end

  def get_headers(body) do
    [body]
    # quick first decode to get the headers, even if the file has no rows
    |> CSV.decode!(headers: false)
    |> Enum.take(1)
    |> List.first()
  end

  def is_dynamic_irve?(headers) do
    "id_pdc_itinerance" in headers && "etat_pdc" in headers
  end

  def time_window(rows) do
    data =
      rows
      |> Enum.map(fn x -> (x["horodatage"] || "???") |> String.slice(0, 10) end)
      |> Enum.to_list()
      |> Enum.sort()

    {List.first(data), List.last(data), Enum.count(data)}
  end
end

# very brittle (false positives & false negatives) at the moment, but helped me a bit already
# Waiting for feedback on https://github.com/frictionlessdata/frictionless-py/issues/1646
defmodule FrictionlessValidator do
  @latest_dynamic_irve_schema "https://schema.data.gouv.fr/schemas/etalab/schema-irve-dynamique/latest/schema-dynamique.json"

  def validate(file_url, schema \\ @latest_dynamic_irve_schema) do
    cmd = "frictionless"
    # NOTE: I tried using `--schema-sync` as an attempt to avoid failure
    # when an optional field column's header is missing.
    args = ["validate", file_url, "--schema", schema, "--json"]
    _debug_cmd = [cmd, args] |> List.flatten() |> Enum.join(" ")

    {output, result} = System.cmd(cmd, args)

    case result do
      0 ->
        {:ok, Jason.decode!(output)}

      1 ->
        {:error, Jason.decode!(output)}
    end
  end

  # quick and dirty parsing
  def errors_summary(output) do
    output["tasks"]
    |> Enum.map(& &1["errors"])
    |> List.flatten()
    |> Enum.map(& &1["message"])
    |> Enum.take(5)
  end
end

IO.puts("========== #{resources |> length()} candidates ==========\n\n")

rows =
  resources
  |> Enum.map(fn r ->
    body = IRVECheck.get_body(r["url"])
    rows = IRVECheck.parse_csv(body)
    headers = IRVECheck.get_headers(body)

    {local_valid, validation_result} = FrictionlessValidator.validate(r["url"])

    File.write!(
      "cache-dir/dyn-irve-" <> r["id"],
      validation_result |> Jason.encode!() |> Jason.Formatter.pretty_print()
    )

    %{
      dataset_url: r["dataset_url"],
      r_id: r["id"],
      organization: r["organization"],
      resource_url: r["url"],
      dynamic_irve_likely: IRVECheck.is_dynamic_irve?(headers),
      time_window: IRVECheck.time_window(rows),
      rows: rows |> length(),
      valid: r["valid"],
      local_valid: local_valid,
      v_date: r["validation_date"],
      schema_name: r["schema_name"],
      schema_version: r["schema_version"]
    }
  end)

IO.inspect(rows, IEx.inspect_opts())

IO.ANSI.Table.start(
  [
    :organization,
    :r_id,
    :dynamic_irve_likely,
    :rows,
    #    :dataset_url,
    :valid,
    :local_valid,
    :v_date,
    :schema_name,
    :schema_version
  ],
  sort_specs: [desc: :rows],
  max_width: :infinity
)

IO.ANSI.Table.format(rows)
IO.ANSI.Table.stop()

IO.ANSI.Table.start(
  [
    :organization,
    :dynamic_irve_likely,
    :rows,
    :dataset_url,
    :valid
  ],
  sort_specs: [desc: :rows],
  max_width: :infinity
)

IO.ANSI.Table.format(rows)
