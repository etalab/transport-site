my_app_root = Path.join(__DIR__, "../..")

defmodule CacheDir do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()
end

cache_dir = CacheDir.cache_dir()

use_cache =
  case System.get_env("CACHE", "NONE") do
    "NONE" ->
      IO.puts("Cache set to :none")
      :none

    "LOW" ->
      IO.puts(
        "Cache set to :partial - only data gouv pagination will be cached (you might need to `rm -rf #{cache_dir}`)"
      )

      :partial

    "ALL" ->
      IO.puts("Cache set to :all - everything is cached (you might need to `rm -rf #{cache_dir}`)")
      :all
  end

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
  def cached_get!(url, options \\ []) do
    options = [
      decode_body: options |> Keyword.get(:decode_body, true),
      enable_cache: options |> Keyword.get(:enable_cache, false)
    ]

    options =
      if options[:enable_cache] do
        Keyword.merge(options, custom_cache_dir: CacheDir.cache_dir())
      else
        options
      end

    Transport.HTTPClient.get!(url, options)
  end
end

# disabling cache by default because one dataset is refreshed very frequently, caching leads to 404
# but letting the CLI decide if this must be cached via `CACHE=LOW` or `ALL`
%{status: 200, body: datasets} = Query.cached_get!(url, enable_cache: use_cache != :none)

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
  def get_body(url, options \\ []) do
    enable_cache = Keyword.get(options, :enable_cache, false)
    # control the decoding ourselves ; by default Req would decode via CSV itself
    %{status: status, body: body} = Query.cached_get!(url, decode_body: false, enable_cache: enable_cache)

    if status != 200 do
      Mix.shell().error("Failed to fetch data for #{url} (http_status=#{status}), halting!")
      System.halt(1)
    end

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
    args = ["validate", file_url, "--schema", schema, "--json", "--format", "csv"]
    # IO.puts [cmd, args] |> List.flatten() |> Enum.join(" ")

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

  # See https://github.com/frictionlessdata/frictionless-py/issues/1646
  # Frictionless will generate a "valid" report for files it did not actually
  # look at it full. As a temporary work-around, I noticed that when this
  # happens, the `labels` field is an empty array, whereas when validation did
  # occur for real, it contains the fields we expect. So this heuristic leverages
  # that empiric observation to try to work-around that uncertainty.
  def did_validation_really_occur?(output) do
    %{
      "tasks" => [
        %{
          "labels" => labels
        }
      ]
    } = output

    "id_pdc_itinerance" in labels
  end

  def really_valid?(output) do
    did_validation_really_occur?(output) &&
      match?(%{"errors" => 0, "warnings" => 0}, output["stats"])
  end
end

IO.puts("========== #{resources |> length()} candidates ==========\n\n")

rows =
  resources
  |> Enum.map(fn r ->
    IO.puts("Processing #{r["id"]} (#{r["dataset_url"]} by #{r["organization"]})...")
    body = IRVECheck.get_body(r["url"], enable_cache: use_cache == :all)
    rows = IRVECheck.parse_csv(body)
    headers = IRVECheck.get_headers(body)

    {local_valid, validation_output} = FrictionlessValidator.validate(r["url"])

    really_local_valid = FrictionlessValidator.really_valid?(validation_output)
    output_file = CacheDir.cache_dir() |> Path.join("dyn-irve-" <> r["id"])

    File.write!(
      output_file,
      validation_output |> Jason.encode!() |> Jason.Formatter.pretty_print()
    )

    %{
      dataset_url: r["dataset_url"],
      r_id: r["id"],
      organization: r["organization"],
      resource_url: r["url"],
      dyn_irve_likely: IRVECheck.is_dynamic_irve?(headers),
      time_window: IRVECheck.time_window(rows),
      rows: rows |> length(),
      valid: r["valid"],
      local_valid: local_valid,
      really_local_valid: really_local_valid,
      frictionless_output_file: output_file,
      v_date: r["validation_date"],
      schema_name: r["schema_name"],
      schema_version: r["schema_version"],
      local_validation_errors: FrictionlessValidator.errors_summary(validation_output),
      local_validation_stats: validation_output |> Map.fetch!("stats")
    }
  end)

IO.inspect(rows, IEx.inspect_opts())

IO.ANSI.Table.start(
  [
    :organization,
    :r_id,
    :dyn_irve_likely,
    :rows,
    #    :dataset_url,
    :valid,
    :local_valid,
    :really_local_valid,
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
    :dyn_irve_likely,
    :rows,
    :dataset_url,
    :valid
  ],
  sort_specs: [desc: :rows],
  max_width: :infinity
)

IO.ANSI.Table.format(rows)
IO.ANSI.Table.stop()

IO.ANSI.Table.start(
  [
    :organization,
    :rows,
    :local_valid,
    :really_local_valid,
    :one_error
  ],
  sort_specs: [desc: :rows],
  max_width: :infinity
)

exploded_rows =
  rows
  |> Enum.flat_map(fn r ->
    r[:local_validation_errors]
    |> Enum.map(fn x -> r |> Map.put(:one_error, x) end)
  end)

IO.ANSI.Table.format(exploded_rows)
IO.ANSI.Table.stop()

rows =
  rows
  |> Enum.map(fn r ->
    Map.update!(r, :local_validation_stats, &inspect/1)
  end)

IO.ANSI.Table.start(
  [
    :organization,
    :rows,
    :local_valid,
    :local_validation_stats,
    :frictionless_output_file
  ],
  sort_specs: [desc: :rows],
  max_width: :infinity
)

IO.ANSI.Table.format(rows)
IO.ANSI.Table.stop()
