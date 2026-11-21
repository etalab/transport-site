# IRVE

IRVE (*infrastructures de recharge pour véhicules électriques*) are electric vehicle charge points. This page explains why transport.data.gouv.fr builds its own national IRVE file, how it works, and what to know before changing it. Details live in the moduledocs of `apps/transport/lib/irve/`.

## Why a consolidation

Each charge point owner (*aménageur*) or operator publishes its own file on data.gouv.fr, following the schema [`etalab/schema-irve-statique`](https://schema.data.gouv.fr/etalab/schema-irve-statique/). A single file is of little use: a public map, a route planner that plans charging stops or a study of charging coverage in France all need one national file. Building it is tedious (invalid data, encodings, duplicates), so we build it once, for every reuser.

data.gouv.fr used to build it for us. We took it over ([epic #4926](https://github.com/etalab/transport-site/issues/4926)) because:
- it was **unstable**: one invalid row excluded all of a producer's charge points until the file was fixed;
- recoverable problems (Latin-1 encoding, `;` separator) excluded whole files;
- the team working with producers couldn't see which files were excluded and why;
- the deduplication rules couldn't be changed, e.g. to prefer some datasets.

As of November 2026: about 1,860 resources, 436,000 rows stored, 181,000 charge points after deduplication.

## How it works

`Transport.Jobs.IRVEConsolidationJob` runs every night at 04:45 UTC:
1. list the data.gouv.fr resources declaring the schema (`Transport.IRVE.Extractor`);
2. download each one, validate it, and store it if it is valid (`Transport.IRVE.Consolidation`, `Transport.IRVE.Validator`, `Transport.IRVE.DatabaseImporter`);
3. export everything stored, deduplicate it, and publish three files (`Transport.IRVE.DatabaseExporter`, `Transport.IRVE.Deduplicator`).

The choices behind it:
- **The last valid version stays.** Only valid files are stored (`DB.IRVEValidFile`, `DB.IRVEValidPDC`). When a producer publishes a broken update, the update is rejected, but the previous version stays in the database, and so does every charge point in it. This is what makes the file stable.
- **A file is valid only if every row is valid.** The producer finds why in the report, or by uploading the file to the site's validator.
- **One validator.** On-demand validation (validation page, type IRVE statique) and the consolidation share `Transport.IRVE.Validator.validate_and_summarize/2`. A producer gets exactly the verdict the consolidation will give.
- **Tolerant reading.** Latin-1 files are converted, `,` and `;` are both accepted, and swapped longitude/latitude are corrected and flagged in `consolidated_is_lon_lat_correct`.
- **Unchanged files are skipped**, by checksum of the downloaded bytes. Most of the run is downloading.
- **Only organizations count as producers**: a dataset published by a person is skipped.

## Deduplication

The same charge point often appears in several files: the aménageur and its operator both publish it, aggregators (Gireve, Qualicharge, Eco-movement) republish their members' data, or a producer publishes a new resource instead of updating the old one.

Duplicates share an `id_pdc_itinerance`, the national id of a charge point. It starts with the operator's prefix (`FR` + 3 characters), registered with AFIREV. For each id, one row is kept:
1. the one from a priority dataset (`apps/transport/priv/irve_prioritary_datasets.yml`);
2. otherwise the most recent `date_maj`;
3. otherwise the most recently updated resource.

The full rules, edge cases included, are in `Transport.IRVE.Deduplicator`'s moduledoc. Each row says why it was kept or removed, in `deduplication_status`.

## Published files

| File | URL | For |
|---|---|---|
| Deduplicated | https://proxy.transport.data.gouv.fr/resource/consolidation-transport-irve-statique | Reusers |
| With duplicates | https://proxy.transport.data.gouv.fr/resource/consolidation-transport-avec-doublons-irve-statique | Analysis: it is what the database holds, with `deduplication_status` on every row |
| Report | https://proxy.transport.data.gouv.fr/resource/consolidation-transport-irve-statique-rapport | The team working with producers: one row per resource, with what happened to it |

The report's `consolidation_status`:
- `import_successful`, `already_up_to_date`: stored;
- `producer_not_an_organization`, `download_failed`, `file_level_errors`, `not_compliant_with_schema`: rejected, and `error_message` says why;
- `error_occurred`: a bug on our side, also sent to Sentry;
- `grace_period`, `soft_deleted`: no longer on data.gouv.fr (next section).

The files are uploaded to the S3 bucket `aggregates`, with a dated copy of each. data.gouv.fr still publishes its own consolidation, and the site's IRVE map data (`Transport.Jobs.IRVEToGeoData`) still comes from it, not from ours.

## Resources removed from data.gouv.fr

A resource can disappear from data.gouv.fr: deleted, its dataset deleted or archived, or its schema declaration removed. Its charge points used to stay in our file forever ([#5702](https://github.com/etalab/transport-site/issues/5702)). Now:
- the first night a resource is missing, its file gets `unlisted_since`;
- after 7 days it gets `soft_deleted_at`: its charge points leave the deduplicated file, and stay in the file with duplicates, flagged `removed_because_soft_deleted`;
- if it comes back, both columns are cleared.

Why wait: resources do come back (a dataset republished, a schema declared again), and a listing glitch can hide a resource for a night. To skip the wait, run the job once with `%{"unlisted_grace_period_days" => 0}`.

## Running it

- **Locally**: `mix run scripts/irve/process-consolidation.exs --destination local_disk --debug --limit 5`. In development, `mix run` sets `WORKER=0` itself (alias in `mix.exs`), so Oban doesn't work through the jobs pending in the database during the run. `local_disk` writes the three files at the repository root, replacing the previous ones; without it they go to the `aggregates-dev` bucket.
- **In production**, only through the job. The script would publish to the production bucket, and its `--erase-existing-data all` empties the IRVE tables.

## Gotchas

- **Stale listing in development.** With `config :transport, :irve_consolidation_caching, true` (in some `config/dev.secret.exs`), the data.gouv.fr listing is cached in `cache-dir/` with no expiry. Resources published since then look removed, and get soft-deleted with a grace period of 0. Turn the flag off, or delete the cached listing, when the listing matters.
- **Memory.** The export reads the database in chunks of 10,000 rows, because loading everything at once ran production out of memory. The deduplication still works on the whole table (about 180 MB): if the job runs out of memory again, look there first.
- **S3 timeouts.** The files are big. An upload timeout is a process exit, not an exception: `Transport.S3.stream_to_s3!/4` sends it to Sentry before letting it crash the job.

## Other IRVE code

- **Dynamic data** (`etalab/schema-irve-dynamique`, the live status of charge points): the proxy aggregates the dynamic feeds into https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-dynamique (`Unlock.DynamicIRVE`).
- **Schema v3**, static, dynamic and tariffs, is coming: seeded generators in `apps/transport/test/support/irve_v3_*` and `scripts/irve/v3/`.
- **Backoffice IRVE dashboard**: an older scan that downloads every resource to count its lines (`Transport.Jobs.AnalyzeIRVEJob`), separate from the consolidation.

## Scripts and analysis

`scripts/irve/` holds the analysis tools, each documented in its header. They download the published files once a day into `cache-dir/irve/`.
- `compare.exs`: our file against data.gouv.fr's, by resource or by operator, with the reason from our report;
- `report_stats.exs`: counts of statuses and errors in a report;
- `superseded-resources.exs`: producers who publish new resources instead of updating;
- `compare-external.exs`, `afirev.exs`: an external file, or the AFIREV operator registry, against our file;
- `dump-consolidation.exs`: export the database without running the consolidation, e.g. after restoring a production backup.

To find out why a resource left the listing, ask data.gouv.fr's API: a 404 on its dataset means the dataset was deleted; a dataset without the resource means the resource was deleted; a resource without `schema.name` means the schema declaration was removed.

To measure the effect of a deduplication change on real data, run `Transport.IRVE.Deduplicator.add_duplicates_column/1` on the published file with duplicates:
- load it as strings, drop `deduplication_status`, and cast `date_maj` and `datagouv_last_modified`;
- check that the rerun gives back the published statuses;
- then change the input or the rules, and compare.

The impact of #5702 was measured this way.
