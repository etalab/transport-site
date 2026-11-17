my_app_root = Path.join(__DIR__, "../..")

defmodule CacheDir do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()
end

cache_dir = CacheDir.cache_dir()

if !File.exists?(cache_dir), do: File.mkdir(cache_dir)

use_cache =
  case System.get_env("CACHE", "NONE") do
    "NONE" ->
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
    {:table_rex, "~> 4.0"}
  ],
  config_path: Path.join(my_app_root, "config/config.exs"),
  lockfile: Path.join(my_app_root, "mix.lock"),
  # only the code is needed, not the app (Oban, Phoenix, DB...)
  start_applications: false
)

{:ok, _} = Application.ensure_all_started(:req)
# hides Req redirect logs
Logger.configure(level: :info)

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

info = fn text -> [:faint, text] |> IO.ANSI.format() |> IO.puts() end
info.("Recherche sur data.gouv des jeux de données au schéma IRVE dynamique :\n  #{url}")

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
      |> Map.put("dataset_id", dataset["id"])
      |> Map.put("dataset_url", dataset["page"])
      |> Map.put("organization", dataset["organization"]["name"])
      |> Map.put("valid", get_in(r, ["extras", "validation-report:valid_resource"]))
      |> Map.put("validation_date", get_in(r, ["extras", "validation-report:validation_date"]))
      |> Map.put("schema_name", get_in(r, ["schema", "name"]))
      |> Map.put("schema_version", get_in(r, ["schema", "version"]))
    end)
  end)
  # our own national consolidation, built from the other resources
  |> Enum.reject(&(&1["url"] == "https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-dynamique"))

info.("""
#{length(datasets["data"])} jeux de données → #{length(resources)} ressources déclarées au schéma IRVE dynamique \
(hors notre consolidation nationale)
Téléchargement et analyse de chaque ressource#{if System.get_env("FRICTIONLESS") == "1", do: " + validation frictionless"}
""")

defmodule IRVECheck do
  alias Explorer.{DataFrame, Series}

  def get_body(url, options \\ []) do
    enable_cache = Keyword.get(options, :enable_cache, false)
    # control the decoding ourselves ; by default Req would decode via CSV itself
    case Query.cached_get!(url, decode_body: false, enable_cache: enable_cache) do
      %{status: 200, body: body} -> {:ok, body}
      %{status: status} -> {:error, "HTTP #{status}"}
    end
  end

  # a broken file must not halt the whole run
  def parse({:error, _} = error), do: error
  def parse({:ok, "<" <> _}), do: {:error, "page HTML, pas un CSV"}
  def parse({:ok, "PK" <> _}), do: {:error, "fichier zip (xlsx ?), pas un CSV"}

  def parse({:ok, body}) do
    delimiter = delimiter(body)

    case DataFrame.load_csv(body, infer_schema_length: 0, delimiter: delimiter) do
      {:ok, df} -> {:ok, df, delimiter}
      {:error, e} -> {:error, e |> Exception.message() |> String.slice(0, 50)}
    end
  end

  # DynamicIRVE only reads `,`, but `;` files are still worth analysing
  defp delimiter(body) do
    header = body |> String.split("\n", parts: 2) |> hd()
    if String.contains?(header, ";") and not String.contains?(header, ","), do: ";", else: ","
  end

  def schema(df) do
    cond do
      has_columns?(df, ~w(id_pdc_itinerance etat_pdc)) -> :dynamic
      has_columns?(df, ~w(id_station_itinerance nom_amenageur)) -> :static
      true -> {:unknown, df |> DataFrame.names() |> Enum.take(3)}
    end
  end

  def last_day(df) do
    if has_columns?(df, ~w(horodatage)) do
      df["horodatage"]
      |> Series.substring(0, 10)
      |> Series.distinct()
      |> Series.to_list()
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)
    end
  end

  # a frozen feed typically has a single value (e.g. 100% "inconnu")
  def occupation(df) do
    if has_columns?(df, ~w(occupation_pdc)) do
      df
      |> DataFrame.frequencies(~w(occupation_pdc))
      |> DataFrame.to_rows()
      |> Enum.map(&{&1["occupation_pdc"], &1["counts"]})
    end
  end

  defp has_columns?(df, columns), do: columns -- DataFrame.names(df) == []
end

# very brittle (false positives & false negatives) at the moment, but helped me a bit already
# Waiting for feedback on https://github.com/frictionlessdata/frictionless-py/issues/1646
defmodule FrictionlessValidator do
  @latest_dynamic_irve_schema "https://schema.data.gouv.fr/schemas/etalab/schema-irve-dynamique/latest/schema-dynamique.json"

  # opt-in via FRICTIONLESS=1, as it requires the `frictionless` CLI
  def validate(file_url, schema \\ @latest_dynamic_irve_schema) do
    if System.get_env("FRICTIONLESS") == "1", do: run(file_url, schema), else: {:skipped, nil}
  end

  defp run(file_url, schema) do
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
  def errors_summary(nil), do: []

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

  def really_valid?(nil), do: nil

  def really_valid?(output) do
    did_validation_really_occur?(output) &&
      match?(%{"errors" => 0, "warnings" => 0}, output["stats"])
  end
end

defmodule Report do
  @spinner ~w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  @icons %{ok: {:green, "✔"}, warning: {:yellow, "▲"}, other_schema: {:cyan, "≠"}, error: {:red, "✖"}}

  # animates a spinner while `fun` runs, returns `{result, seconds}`
  def with_spinner(label, fun) do
    spinner = spawn(fn -> spin(label, 0) end)
    {microseconds, result} = :timer.tc(fun)
    Process.exit(spinner, :kill)
    IO.write("\r\e[2K")
    {result, microseconds / 1_000_000}
  end

  defp spin(label, i) do
    IO.write("\r#{Enum.at(@spinner, rem(i, length(@spinner)))} #{label}")
    Process.sleep(80)
    spin(label, i + 1)
  end

  def verdict(%{error: error}), do: {:error, [error]}
  def verdict(%{schema: :static}), do: {:other_schema, ["schéma IRVE statique"]}
  def verdict(%{schema: {:unknown, columns}}), do: {:other_schema, ["autre schéma : #{Enum.join(columns, ", ")}…"]}

  def verdict(r) do
    warnings =
      [
        r.delimiter == ";" && "séparateur « ; » (non lu par DynamicIRVE)",
        stale?(r.last_day) && "horodatage > 7 jours",
        match?([_], r.occupation) && "figé"
      ]
      |> Enum.filter(& &1)

    # informative only: a live feed is worth consuming even if invalid
    info = if r.valid != true, do: ["invalide sur data.gouv"], else: []

    {if(warnings == [], do: :ok, else: :warning), warnings ++ info}
  end

  defp stale?(day) do
    case Date.from_iso8601(day || "") do
      {:ok, date} -> Date.diff(Date.utc_today(), date) > 7
      _ -> true
    end
  end

  def print(%{verdict: {status, notes}} = r) do
    {color, icon} = @icons[status]
    details = if status in [:ok, :warning], do: [stats(r), "  "], else: []
    seconds = :erlang.float_to_binary(r.seconds, decimals: 1) <> "s"

    [color, icon, :reset, " ", String.pad_trailing(r.organization, 22), :faint, String.pad_leading(seconds, 5), :reset]
    |> Kernel.++(["  ", details, color, Enum.join(notes, ", ")])
    |> IO.ANSI.format()
    |> IO.puts()

    [:faint, "  ", r.dataset_url] |> IO.ANSI.format() |> IO.puts()
  end

  defp stats(r) do
    shares = r.occupation |> Enum.take(3) |> Enum.map_join(" · ", fn {k, n} -> "#{k} #{round(100 * n / r.rows)}%" end)

    [
      r.rows |> thousands() |> String.pad_leading(7),
      " PDC  → ",
      r.last_day || "?",
      "  ",
      String.pad_trailing(shares, 36)
    ]
  end

  defp thousands(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+$)/, " ")

  def summary(rows, seconds) do
    counts = Enum.frequencies_by(rows, &elem(&1.verdict, 0))

    [:bright, "\n#{length(rows)} ressources", :reset]
    |> Kernel.++(
      for s <- [:ok, :warning, :other_schema, :error],
          do: [" · ", elem(@icons[s], 0), "#{counts[s] || 0} #{elem(@icons[s], 1)}", :reset]
    )
    |> Kernel.++([:faint, " · #{round(seconds)}s"])
    |> IO.ANSI.format()
    |> IO.puts()
  end
end

started_at = System.monotonic_time(:millisecond)

rows =
  resources
  |> Enum.map(fn r ->
    {row, seconds} =
      Report.with_spinner(r["organization"], fn ->
        # stable url: frequently refreshed resources get a new `r["url"]` during the run
        analysis =
          case r["latest"] |> IRVECheck.get_body(enable_cache: use_cache == :all) |> IRVECheck.parse() do
            {:ok, df, delimiter} ->
              %{
                schema: IRVECheck.schema(df),
                delimiter: delimiter,
                last_day: IRVECheck.last_day(df),
                occupation: IRVECheck.occupation(df),
                rows: Explorer.DataFrame.n_rows(df)
              }

            {:error, error} ->
              %{error: error}
          end

        {local_valid, validation_output} = FrictionlessValidator.validate(r["latest"])

        really_local_valid = FrictionlessValidator.really_valid?(validation_output)
        output_file = CacheDir.cache_dir() |> Path.join("dyn-irve-" <> r["id"])

        if validation_output do
          File.write!(
            output_file,
            validation_output |> Jason.encode!() |> Jason.Formatter.pretty_print()
          )
        end

        Map.merge(analysis, %{
          dataset_id: r["dataset_id"],
          dataset_url: r["dataset_url"],
          download_url: "https://www.data.gouv.fr/api/1/datasets/r/#{r["id"]}",
          organization: r["organization"],
          valid: r["valid"],
          local_valid: local_valid,
          really_local_valid: really_local_valid,
          frictionless_output_file: output_file,
          local_validation_errors: FrictionlessValidator.errors_summary(validation_output),
          local_validation_stats: validation_output && validation_output["stats"]
        })
      end)

    row = Map.merge(row, %{seconds: seconds, verdict: Report.verdict(row)})
    Report.print(row)
    row
  end)

Report.summary(rows, (System.monotonic_time(:millisecond) - started_at) / 1000)

defmodule Display do
  def print_table(data, columns, opts \\ []) do
    sort_key = Keyword.get(opts, :sort_key, :rows)
    title = Keyword.get(opts, :title)
    sorted = Enum.sort_by(data, & &1[sort_key], :desc)
    headers = columns |> Enum.map(&to_string/1)

    table_rows =
      sorted
      |> Enum.map(fn row ->
        columns |> Enum.map(fn col -> cell(row[col]) end)
      end)

    TableRex.quick_render!(table_rows, headers, title)
    |> IO.puts()
  end

  defp cell(nil), do: ""
  defp cell(value) when is_binary(value), do: value
  defp cell(value), do: inspect(value)
end

if System.get_env("FRICTIONLESS") == "1" do
  exploded_rows =
    rows
    |> Enum.flat_map(fn r ->
      r[:local_validation_errors]
      |> Enum.map(fn x -> r |> Map.put(:one_error, x) end)
    end)

  Display.print_table(
    exploded_rows,
    [
      :organization,
      :rows,
      :local_valid,
      :really_local_valid,
      :one_error
    ],
    title: "Erreurs de validation détaillées (une ligne par erreur par ressource)"
  )

  Display.print_table(rows, [
    :organization,
    :rows,
    :local_valid,
    :local_validation_stats,
    :frictionless_output_file
  ])
end

# Generate YAML config for healthy resources only
yaml_rows =
  rows
  |> Enum.filter(&match?({:ok, _}, &1.verdict))
  |> Enum.sort_by(& &1[:rows], :desc)

[:bright, "\nConfiguration YAML (ressources ✔)\n"] |> IO.ANSI.format() |> IO.puts()

yaml_rows
|> Enum.each(fn r ->
  slug = r[:organization] |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

  IO.puts("""
        - identifier: #{r[:dataset_id]}
          slug: #{slug}
          target_url: #{r[:download_url]}\
  """)
end)
