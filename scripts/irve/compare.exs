# mix run --no-start scripts/irve/compare.exs [--by resource|prefix] [--report source] [source ...]
#
# Compares IRVE static consolidations. Prints counts for each source; with exactly two sources, also the keys
# (data.gouv resources, or operator prefixes with `--by prefix`) found on one side only or with a different PDC count.
# Resources are annotated with the outcome of our consolidation from its report, to tell why one is missing.
#
# source: transport, transport-avec-doublons, datagouv, report, a local CSV path or a URL. Downloads are cached for
# the day in cache-dir/irve/ (see support/sources.exs).
# Default: transport-avec-doublons datagouv (the file with duplicates is what we have in DB: in the deduplicated one,
# a resource whose PDCs are all duplicates looks missing).
# --report defaults to the published report; it must come from the same run as our file (after a local run:
# --report consolidation_transport_irve_statique_rapport.csv).

Code.require_file("support/sources.exs", __DIR__)

defmodule Compare do
  require Explorer.DataFrame, as: DF
  alias Explorer.Series
  alias IRVEScripts.Sources

  @columns [
    "id_pdc_itinerance",
    "datagouv_resource_id",
    "datagouv_dataset_id",
    "datagouv_organization_or_owner",
    "nom_operateur"
  ]

  def run(argv) do
    {opts, sources} = OptionParser.parse!(argv, strict: [by: :string, report: :string])
    by = Keyword.get(opts, :by, "resource")
    if by not in ["resource", "prefix"], do: raise(ArgumentError, "--by must be resource or prefix")
    sources = if sources == [], do: ["transport-avec-doublons", "datagouv"], else: sources

    loaded = Enum.map(sources, &{&1, &1 |> Sources.resolve() |> Sources.load(@columns)})

    print_counts(loaded)

    with [{name_a, df_a}, {name_b, df_b}] <- loaded do
      report = if by == "resource", do: load_report(Keyword.get(opts, :report, "report")), else: %{}
      IO.puts("\na = #{name_a}, b = #{name_b}")
      a = counts_by(df_a, by, report)
      b = counts_by(df_b, by, report)
      print_only(a, b, "#{plural(by)} only in a", by)
      print_only(b, a, "#{plural(by)} only in b", by)
      print_deltas(a, b, by)
    end
  end

  defp print_counts(loaded) do
    loaded
    |> Enum.map(fn {source, df} ->
      rows = DF.n_rows(df)
      distinct_pdc = Series.n_distinct(df["id_pdc_itinerance"])

      %{
        "source" => source,
        "rows" => rows,
        "distinct_pdc" => distinct_pdc,
        "duplicate_rows" => rows - distinct_pdc,
        "resources" => Series.n_distinct(df["datagouv_resource_id"]),
        "prefixes" => df |> DF.drop_nil("prefix") |> DF.pull("prefix") |> Series.n_distinct()
      }
    end)
    |> DF.new()
    |> DF.select(["source", "rows", "distinct_pdc", "duplicate_rows", "resources", "prefixes"])
    |> DF.print(limit: :infinity)
  end

  # resource id → report status (`consolidation_status`, or `resource_status` for files no longer on data.gouv)
  defp load_report(source) do
    source
    |> Sources.resolve()
    |> DF.from_csv!(
      columns: ["resource_id", "resource_status", "consolidation_status", "error_message"],
      infer_schema_length: 0
    )
    |> DF.to_rows()
    |> Map.new(fn row ->
      {row["resource_id"],
       %{
         "report_status" => row["consolidation_status"] || row["resource_status"],
         "error" => row["error_message"] && row["error_message"] |> String.replace(~r/\s+/, " ") |> String.slice(0, 70)
       }}
    end)
  end

  defp counts_by(df, "resource", report) do
    df
    |> DF.group_by("datagouv_resource_id")
    |> DF.summarise(
      pdc: n_distinct(id_pdc_itinerance),
      dataset_id: first(datagouv_dataset_id),
      organization: first(datagouv_organization_or_owner)
    )
    |> DF.rename(datagouv_resource_id: "key")
    |> to_map()
    |> Map.new(fn {key, row} ->
      {key, Map.merge(row, Map.get(report, key, %{"report_status" => "not in report", "error" => nil}))}
    end)
  end

  defp counts_by(df, "prefix", _report) do
    df
    |> DF.drop_nil("prefix")
    |> DF.group_by("prefix")
    |> DF.summarise(pdc: n_distinct(id_pdc_itinerance), nom_operateur: first(nom_operateur))
    |> DF.rename(prefix: "key")
    |> to_map()
  end

  defp to_map(df), do: df |> DF.to_rows() |> Map.new(&{&1["key"], &1})

  defp labels("resource"), do: ["dataset_id", "organization", "report_status", "error"]
  defp labels("prefix"), do: ["nom_operateur"]

  defp plural("resource"), do: "resources"
  defp plural("prefix"), do: "prefixes"

  defp print_only(side, other, title, by) do
    rows = side |> Map.drop(Map.keys(other)) |> Map.values() |> Enum.sort_by(& &1["pdc"], :desc)
    IO.puts("\n== #{length(rows)} #{title} (#{rows |> Enum.map(& &1["pdc"]) |> Enum.sum()} PDC) ==")
    if by == "resource", do: print_by_report_status(rows)
    print_rows(rows, ["key", "pdc" | labels(by)])
  end

  defp print_by_report_status(rows) do
    rows
    |> Enum.group_by(& &1["report_status"])
    |> Enum.map(fn {status, rows} ->
      %{"report_status" => status, "resources" => length(rows), "pdc" => rows |> Enum.map(& &1["pdc"]) |> Enum.sum()}
    end)
    |> Enum.sort_by(& &1["pdc"], :desc)
    |> print_rows(["report_status", "resources", "pdc"])
  end

  defp print_deltas(a, b, by) do
    rows =
      a
      |> Enum.filter(fn {key, row} -> Map.has_key?(b, key) and b[key]["pdc"] != row["pdc"] end)
      |> Enum.map(fn {key, row} ->
        Map.merge(row, %{"pdc_a" => row["pdc"], "pdc_b" => b[key]["pdc"], "delta" => b[key]["pdc"] - row["pdc"]})
      end)
      |> Enum.sort_by(&abs(&1["delta"]), :desc)

    IO.puts("\n== #{length(rows)} #{plural(by)} in both with a different PDC count ==")
    print_rows(rows, ["key", "pdc_a", "pdc_b", "delta" | labels(by)])
  end

  defp print_rows([], _columns), do: :ok
  defp print_rows(rows, columns), do: rows |> DF.new() |> DF.select(columns) |> DF.print(limit: :infinity)
end

Compare.run(System.argv())
