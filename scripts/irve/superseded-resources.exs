# mix run --no-start scripts/irve/superseded-resources.exs [--min-coverage 0.1] [--details] [--csv path] [source]
#
# Detects "sliding IRVE static resources", where a producer publishes a new resource instead of updating the existing
# one, so the old resource stays in the dataset and its PDC stay in the consolidation. This goes against our publication
# guidelines, see https://doc.transport.data.gouv.fr/administration-des-donnees/guide-de-publication/mettre-a-jour-des-donnees
# ("Mettre à jour ou publier une nouvelle ressource ?"), and is one of the possible causes listed in
# https://github.com/etalab/transport-site/issues/5702.
# A resource is a candidate when its `id_pdc_itinerance` are also found in a more recent (`datagouv_last_modified`)
# resource of the same dataset.
# coverage = share of the resource's PDC found in newer resources; resources above --min-coverage are listed.
#
# Input: no database, no data.gouv API call. The only input is the public consolidated file *with duplicates*
# (`transport-avec-doublons`, downloaded through the proxy, see support/sources.exs). Our consolidation builds it
# from the data.gouv catalog and adds the data.gouv dataset/resource ids and `last_modified` on each row.
# The deduplicated file can't be used: it keeps a single row per PDC, so the overlap between resources is lost.

Code.require_file("support/sources.exs", __DIR__)

require Explorer.DataFrame, as: DF
alias Explorer.Series
alias IRVEScripts.Sources

{opts, args} = OptionParser.parse!(System.argv(), strict: [min_coverage: :float, details: :boolean, csv: :string])
min_coverage = Keyword.get(opts, :min_coverage, 0.1)

rows =
  (List.first(args) || "transport-avec-doublons")
  |> Sources.resolve()
  |> Sources.load([
    "id_pdc_itinerance",
    "datagouv_dataset_id",
    "datagouv_resource_id",
    "datagouv_last_modified",
    "datagouv_organization_or_owner",
    "dataset_title"
  ])

pdc = DF.filter(rows, prefix_bucket != "non concerné" and prefix_bucket != "unparseable")

resources =
  pdc
  |> DF.group_by(["datagouv_organization_or_owner", "dataset_title", "datagouv_dataset_id", "datagouv_resource_id"])
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

# per-resource details (coverage etc.)
if opts[:details], do: DF.print(report, limit: :infinity)
if opts[:csv], do: DF.to_csv!(report, opts[:csv])

# one line per dataset, to follow up with producers
datasets =
  report
  |> DF.group_by(["datagouv_organization_or_owner", "dataset_title", "datagouv_dataset_id"])
  |> DF.summarise(sliding_resources: size(datagouv_resource_id), covered: sum(covered))
  |> DF.sort_by(desc: sliding_resources, desc: covered)

# GitHub markdown checklist, to paste in a ticket
IO.puts("\n== Datasets (markdown) ==\n")

for d <- DF.to_rows(datasets) do
  url = "https://www.data.gouv.fr/datasets/#{d["datagouv_dataset_id"]}"
  count = d["sliding_resources"]
  label = if count == 1, do: "ressource glissante", else: "ressources glissantes"

  IO.puts(
    "- [ ] **#{String.trim(d["datagouv_organization_or_owner"])}** : [#{d["dataset_title"]}](#{url}) " <>
      "(#{count} #{label})"
  )
end

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
