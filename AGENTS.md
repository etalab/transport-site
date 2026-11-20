# AGENTS.md

Instructions for AI coding agents working in this repository. Setup instructions for humans are in [README.md](README.md).

## The project

transport.data.gouv.fr is the French National Access Point for mobility data. It catalogs the transport datasets published on data.gouv.fr, validates them (GTFS, NeTEx, GTFS-RT, table schemas, IRVE), builds national consolidations (IRVE, BNLC, …) and proxies real-time feeds. User documentation: https://doc.transport.data.gouv.fr.

It is a Phoenix umbrella with PostgreSQL (PostGIS) and Oban:
- `apps/transport`: the web app, the background jobs and the proxy (`lib/unlock/`). Ecto schemas are `DB.*` modules in `lib/db/`; jobs are in `lib/jobs/`; the web layer is in `lib/transport_web/`.
- `apps/shared`: code shared with the transport app, and the schema files in `meta/`.

Two environment variables pick what a node runs (`config/runtime.exs`): `WEBSERVER` and `WORKER`. In production, some nodes serve the site and others run the jobs; in development a node does both, and `mix run` sets `WORKER=0` (alias in `mix.exs`). Local secrets and settings go in `config/dev.secret.exs`, which git ignores.

## Rules

- **Read [docs/code_style.md](docs/code_style.md) before writing any code, template or test.** It holds the project's conventions; this file doesn't repeat them.
- **Never run anything against production or Clever Cloud**, read-only included: no database queries, no S3, no IEx on a node, no `clever` command. Write the commands down and hand them to a human.

## Read before working on

- **IRVE** (electric vehicle charge points): [docs/irve.md](docs/irve.md).
- **A technical choice**: [docs/adr/](docs/adr/). Accepted ADRs are rules.
- **The domain and the data**: [glossary.md](glossary.md), [docs/data_model.livemd](docs/data_model.livemd).
- **A maintenance task** (upgrades, GTFS validator, GTFS-RT protobuf files, PostgreSQL collation, staging, logs…): [docs/learning_track.md](docs/learning_track.md) goes beyond onboarding with these procedures. Those touching Clever Cloud are for humans (see Rules).

## Commands

- Development server: `mix phx.server`, on http://localhost:5000.
- Tests:
  - everything: `mix test`, which also creates and migrates the test database;
  - one file or one test: `mix cmd --app transport mix test --color test/path/to/file_test.exs:42`, with the path relative to the app. This doesn't migrate: after adding a migration, run `MIX_ENV=test mix ecto.migrate` first;
  - tests tagged `:external`, `:transport_tools` or `:timescaledb` are skipped locally (`apps/transport/test/test_helper.exs`).
- CI (`.github/workflows/test.yml`) fails on any of these:
  - `mix test --warnings-as-errors`: Elixir 1.20 type-checks the code, and its warnings count;
  - `mix format --check-formatted`;
  - `mix credo --strict`;
  - `mix gettext.extract --check-up-to-date`;
  - `mix npm "run linter:ecma"`, `mix npm "run linter:sass"`.

  `mix check_all` runs all of them, but without `--warnings-as-errors`. Warnings printed while dependencies compile are not ours and don't fail the build.
- Dialyzer is not in CI. `mix dialyzer`, run locally, is the only check of `@spec`: run it after big upgrades, or when changing `@spec`, `@callback` or behaviours.
- Translations: French is the default locale. After adding a string, run `mix gettext.extract --merge` and translate it in both `apps/transport/priv/gettext/fr` and `en`.

## Local setup

Most agents (Codex, Cursor, GitHub Copilot, Claude Code, …) read this file on their own. Claude Code does so only when there is no `CLAUDE.md` or `CLAUDE.local.md` in the repository or above it.

To add your own rules, write them in your agent's personal file, import this one from it, and keep that file out of git. Example for Claude Code, a `CLAUDE.local.md` at the repository root, listed in `.git/info/exclude`:

```markdown
@AGENTS.md
@docs/code_style.md

## My rules

- Stop before each commit: I review and commit myself.
- Write PR descriptions in French.

…
```
