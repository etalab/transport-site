# mix run --no-start scripts/irve/compare-external.exs [--id-column NAME] [--source S] [--hunt S] [--report S] external.csv
#
# What does an external IRVE static CSV (schema column names; ids possibly written with `*` separators and extra
# trailing components) have that our consolidation misses, and where to hunt for it?
#
# Each external PDC is looked up in our consolidation:
# - by id: normalized id (see support/sources.exs), as is or without its last 1 or 2 `*` components;
# - else by location: a PDC in the same or a neighbouring 1e-4° cell of `coordonneesXY` (~10-20 m; neighbours
#   because coordinates may be truncated, ours are exported with 5 decimals);
# - else it is looked up the same way in the `--hunt` consolidation (data.gouv's):
#   - found there under an id we have: in ours after all;
#   - found there otherwise: missing, with the data.gouv resource holding it and why we don't have it (our report);
#   - not found: missing and not published on data.gouv, the operator / aménageur is the one to ask.
#
# --id-column: id column of the external file (default: id_pdc_itinerance)
# --source: our consolidation (default: transport) · --hunt: default datagouv · --report: default report
# (sources: see compare.exs)

Code.require_file("support/sources.exs", __DIR__)

defmodule CompareExternal do
  alias Explorer.DataFrame, as: DF
  alias IRVEScripts.Sources

  def run(argv) do
    {opts, [external_path]} =
      OptionParser.parse!(argv, strict: [id_column: :string, source: :string, hunt: :string, report: :string])

    hunt_source = Keyword.get(opts, :hunt, "datagouv")

    ours =
      opts
      |> Keyword.get(:source, "transport")
      |> Sources.resolve()
      |> Sources.load(["id_pdc_itinerance", "coordonneesXY"])

    ours_index = index(ours, fn _row -> true end)
    ours_by_prefix = ours["prefix"] |> Explorer.Series.to_list() |> Enum.frequencies()

    hunt =
      hunt_source
      |> Sources.resolve()
      |> Sources.load([
        "id_pdc_itinerance",
        "coordonneesXY",
        "datagouv_resource_id",
        "datagouv_dataset_id",
        "datagouv_organization_or_owner"
      ])

    hunt_index = index(hunt, &{&1["datagouv_resource_id"], Sources.normalize_id(&1["id_pdc_itinerance"])})
    resources = hunt |> DF.to_rows() |> Map.new(&{&1["datagouv_resource_id"], &1})
    report = Sources.load_report(Keyword.get(opts, :report, "report"))

    external =
      external_path
      |> DF.from_csv!(
        columns: [Keyword.get(opts, :id_column, "id_pdc_itinerance"), "nom_operateur", "nom_amenageur", "coordonneesXY"],
        infer_schema_length: 0
      )
      |> DF.rename([{Keyword.get(opts, :id_column, "id_pdc_itinerance"), "id"}])
      |> DF.to_rows()
      |> Enum.map(fn row ->
        {bucket, prefix} = Sources.prefix_bucket(row["id"])
        row = Map.merge(row, %{"bucket" => bucket, "prefix" => prefix || "(#{bucket})"})

        case match(row, ours_index) do
          "missing" -> hunt(row, hunt_index, ours_index, report, hunt_source)
          match -> Map.put(row, "match", match)
        end
      end)

    missing = Enum.filter(external, &(&1["match"] == "missing"))

    {found, not_found} = Enum.split_with(missing, & &1["resource_id"])

    print_overview(external, ours, ours_by_prefix, missing, found, not_found, hunt_source)
    print_found(found, resources, report, hunt_source)
    print_not_found(not_found, external, ours_by_prefix, hunt_source)
  end

  defp hunt(row, hunt_index, {ours_ids, _}, report, hunt_source) do
    case lookup(row, hunt_index) do
      {_resource_id, hunt_id} when is_map_key(ours_ids, hunt_id) ->
        Map.put(row, "match", "via #{hunt_source} id")

      {resource_id, _hunt_id} ->
        where = get_in(report, [resource_id, "report_status"]) || "not in report"
        Map.merge(row, %{"match" => "missing", "resource_id" => resource_id, "where" => where})

      nil ->
        Map.merge(row, %{"match" => "missing", "resource_id" => nil})
    end
  end

  defp print_overview(external, ours, ours_by_prefix, missing, found, not_found, hunt_source) do
    total = length(external)
    pct = fn n -> "#{n} (#{Float.round(100 * n / total, 1)}%)" end
    matches = Enum.frequencies_by(external, & &1["match"])

    IO.puts("""
    Ours: #{DF.n_rows(ours)} PDC, #{map_size(ours_by_prefix)} prefixes
    External: #{total} PDC, #{external |> Enum.uniq_by(& &1["prefix"]) |> length()} prefixes
      in ours, same id: #{pct.(Map.get(matches, "id", 0))}
      in ours, same location: #{pct.(Map.get(matches, "location", 0))}
      in ours, under #{hunt_source}'s id: #{pct.(Map.get(matches, "via #{hunt_source} id", 0))}
      missing from ours: #{pct.(length(missing))}
        on #{hunt_source}: #{pct.(length(found))} in #{found |> Enum.uniq_by(& &1["resource_id"]) |> length()} resources
        not on #{hunt_source}: #{pct.(length(not_found))}\
    """)
  end

  defp print_found(found, resources, report, hunt_source) do
    IO.puts("\n== Missing PDCs found on #{hunt_source}, by our report status for their resource ==")

    found
    |> Enum.group_by(& &1["where"])
    |> Enum.map(fn {where, rows} ->
      %{
        "report_status" => where,
        "missing" => length(rows),
        "resources" => rows |> Enum.uniq_by(& &1["resource_id"]) |> length()
      }
    end)
    |> Enum.sort_by(& &1["missing"], :desc)
    |> print_rows(["report_status", "missing", "resources"])

    IO.puts("\n== #{hunt_source} resources holding missing PDCs (top 30) ==")

    found
    |> Enum.frequencies_by(& &1["resource_id"])
    |> Enum.map(fn {resource_id, count} ->
      resource = resources[resource_id]

      %{
        "resource_id" => resource_id,
        "missing" => count,
        "report_status" => get_in(report, [resource_id, "report_status"]) || "not in report",
        "error" => get_in(report, [resource_id, "error"]),
        "dataset_id" => resource["datagouv_dataset_id"],
        "organization" => resource["datagouv_organization_or_owner"]
      }
    end)
    |> Enum.sort_by(& &1["missing"], :desc)
    |> Enum.take(30)
    |> print_rows(["resource_id", "missing", "report_status", "organization", "dataset_id", "error"])
  end

  defp print_not_found(not_found, external, ours_by_prefix, hunt_source) do
    external_by_prefix = Enum.frequencies_by(external, & &1["prefix"])

    prefixes =
      not_found
      |> Enum.group_by(& &1["prefix"])
      |> Enum.map(fn {prefix, rows} ->
        %{
          "prefix" => prefix,
          "missing" => length(rows),
          "external" => external_by_prefix[prefix],
          "ours" => Map.get(ours_by_prefix, prefix, 0),
          "nom_operateur" => most_frequent(rows, "nom_operateur"),
          "nom_amenageur" => most_frequent(rows, "nom_amenageur")
        }
      end)
      |> Enum.sort_by(& &1["missing"], :desc)

    absent = Enum.filter(prefixes, &(&1["ours"] == 0))

    IO.puts(
      "\n== Missing PDCs not on #{hunt_source}, by operator prefix: #{length(prefixes)} prefixes, " <>
        "#{length(absent)} absent from ours (#{absent |> Enum.map(& &1["missing"]) |> Enum.sum()} PDC) (top 40) =="
    )

    prefixes
    |> Enum.take(40)
    |> print_rows(["prefix", "missing", "external", "ours", "nom_operateur", "nom_amenageur"])

    IO.puts("\n== Missing PDCs not on #{hunt_source}, by aménageur (top 30) ==")

    not_found
    |> Enum.group_by(& &1["nom_amenageur"])
    |> Enum.map(fn {amenageur, rows} ->
      prefixes = rows |> Enum.map(& &1["prefix"]) |> Enum.uniq() |> Enum.join(" ")
      %{"nom_amenageur" => amenageur, "missing" => length(rows), "prefixes" => prefixes}
    end)
    |> Enum.sort_by(& &1["missing"], :desc)
    |> Enum.take(30)
    |> print_rows(["nom_amenageur", "missing", "prefixes"])
  end

  # normalized id → value and location → value, `value` computed from each row
  defp index(df, value) do
    rows = DF.to_rows(df)
    ids = rows |> Map.new(&{Sources.normalize_id(&1["id_pdc_itinerance"]), value.(&1)}) |> Map.delete(nil)
    locations = rows |> Map.new(&{location(&1["coordonneesXY"]), value.(&1)}) |> Map.delete(nil)
    {ids, locations}
  end

  defp match(row, {ids, locations}) do
    cond do
      Enum.any?(candidates(row["id"]), &Map.has_key?(ids, &1)) -> "id"
      Enum.any?(near(location(row["coordonneesXY"])), &Map.has_key?(locations, &1)) -> "location"
      true -> "missing"
    end
  end

  defp lookup(row, {ids, locations}) do
    Enum.find_value(candidates(row["id"]), &ids[&1]) ||
      Enum.find_value(near(location(row["coordonneesXY"])), &locations[&1])
  end

  # the id as is, then without its last 1 or 2 `*` components
  defp candidates(nil), do: []

  defp candidates(id) do
    parts = id |> String.trim_trailing("*") |> String.split("*")
    for drop <- 0..2, drop < length(parts), do: parts |> Enum.drop(-drop) |> Enum.join() |> Sources.normalize_id()
  end

  # 1e-4° grid cell of `coordonneesXY`
  defp location(nil), do: nil

  defp location(coordinates) do
    case Regex.scan(~r/-?\d+(?:\.\d+)?/, coordinates) do
      [[x], [y] | _] -> {cell(x), cell(y)}
      _ -> nil
    end
  end

  defp cell(number), do: number |> Float.parse() |> elem(0) |> Kernel.*(10_000) |> floor()

  defp near(nil), do: []
  defp near({x, y}), do: for(dx <- -1..1, dy <- -1..1, do: {x + dx, y + dy})

  defp most_frequent(rows, key), do: rows |> Enum.frequencies_by(& &1[key]) |> Enum.max_by(&elem(&1, 1)) |> elem(0)

  defp print_rows([], _columns), do: :ok
  defp print_rows(rows, columns), do: rows |> DF.new() |> DF.select(columns) |> DF.print(limit: :infinity)
end

CompareExternal.run(System.argv())
