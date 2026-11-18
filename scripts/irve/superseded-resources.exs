# mix run --no-start scripts/irve/superseded-resources.exs [--min-coverage 0.1] [--csv path] [source]
#
# Candidates for producers publishing a new resource instead of updating the existing one
# (https://github.com/etalab/transport-site/issues/5702): resources whose `id_pdc_itinerance` are also found in a
# more recent (`datagouv_last_modified`) resource of the same dataset.
# coverage = share of the resource's PDC found in newer resources; resources above --min-coverage are listed.
#
# source: defaults to transport-avec-doublons (all resources in DB), see support/sources.exs.

Code.require_file("support/sources.exs", __DIR__)

require Explorer.DataFrame, as: DF
alias Explorer.Series
alias IRVEScripts.Sources

{opts, args} = OptionParser.parse!(System.argv(), strict: [min_coverage: :float, csv: :string])
min_coverage = Keyword.get(opts, :min_coverage, 0.1)

rows =
  (List.first(args) || "transport-avec-doublons")
  |> Sources.resolve()
  |> Sources.load([
    "id_pdc_itinerance",
    "datagouv_dataset_id",
    "datagouv_resource_id",
    "datagouv_last_modified",
    "datagouv_organization_or_owner"
  ])

pdc = DF.filter(rows, prefix_bucket != "non concerné" and prefix_bucket != "unparseable")

resources =
  pdc
  |> DF.group_by(["datagouv_organization_or_owner", "datagouv_dataset_id", "datagouv_resource_id"])
  |> DF.summarise(pdc: n_distinct(id_pdc_itinerance), last_modified: first(datagouv_last_modified))
  |> DF.sort_by(asc: last_modified, asc: datagouv_resource_id)
  # recency rank, only compared within a dataset
  |> DF.mutate(rank: row_index(datagouv_resource_id))

ids =
  pdc
  |> DF.distinct(["datagouv_dataset_id", "datagouv_resource_id", "id_pdc_itinerance"])
  |> DF.join(DF.select(resources, ["datagouv_resource_id", "rank"]), on: "datagouv_resource_id")

covered =
  ids
  |> DF.join(DF.rename(ids, datagouv_resource_id: "newer_resource_id", rank: "newer_rank"),
    on: ["datagouv_dataset_id", "id_pdc_itinerance"]
  )
  |> DF.filter(newer_rank > rank)
  |> DF.group_by("datagouv_resource_id")
  |> DF.summarise(covered: n_distinct(id_pdc_itinerance))

report =
  resources
  |> DF.join(covered, on: "datagouv_resource_id")
  |> DF.mutate(coverage: round(covered / pdc, 2))
  |> DF.filter(coverage >= ^min_coverage)
  |> DF.sort_by(asc: datagouv_dataset_id, asc: rank)
  |> DF.discard("rank")

DF.print(report, limit: :infinity)
if opts[:csv], do: DF.to_csv!(report, opts[:csv])

candidate_ids = report["datagouv_resource_id"]
removed_rows = rows |> DF.filter(datagouv_resource_id in ^candidate_ids) |> DF.n_rows()

IO.puts("""

== Summary (coverage >= #{min_coverage}) ==
Candidate resources: #{DF.n_rows(report)} in #{Series.n_distinct(report["datagouv_dataset_id"])} datasets
PDC also in a newer resource: #{Series.sum(report["covered"])}
PDC only in candidate resources (upper bound): #{Series.sum(report["pdc"]) - Series.sum(report["covered"])}
Rows removed from the file with duplicates: #{removed_rows} / #{DF.n_rows(rows)} \
(-#{Float.round(removed_rows / DF.n_rows(rows) * 100, 1)} %)
""")
