This guide tracks useful steps to learn how to maintain and modify this system.

### Discover the PAN public website

* Go to https://transport.data.gouv.fr and explore the various public pages (home, search, details)
* Read the [user documentation](https://doc.transport.data.gouv.fr) to understand the purpose and overall process

### Discover the PAN admin dashboard

* Ask the team to get access to the admin dashboard
* Expect a bit of delay / cache refresh period
* Get into the dashboard and go around (via the "Administration" top link)

### Run the PAN site locally (simple version)

* Install the required tooling (Elixir/Erlang/Node/Postgres) - see readme
* Restore a production database - see readme
* Ask the team how to fill `.envrc` for minimal use (this will be improved later to avoid that)
* Do not attempt to install the "validator" yet, nor to access the admin backoffice

### Run the test suite locally

* Double-check `.envrc` values (this requirement will go away later)
* Make sure to run ChromeDriver in a way or another
* Run the default `mix test` suite (which excludes tests with special needs)
* Run the full suite with `RUN_ALL` (see readme, this includes tests with special needs e.g. ChromeDriver)
* Learn how to run a single test (see readme), as this is very useful for debugging
* :warning: All the tests should pass locally! If they don't, file an issue

### Understand the "stats" page

* Entry point for bizdev questions on data quality
* Look at `_maps.html.eex` and `map.js`
* Search the code responsible for `quality_features`

### Run a manual GTFS validation (on the server)

* Go to https://transport.data.gouv.fr
* Click on "Analyser la qualité d'un fichier GTFS"
* Find a small GTFS file
* Check the result

### Discover the HTTP routes served by the application

* Run `mix phx.routes TransportWeb.Router` locally
  * Examine the listed routes
  * Check-out `apps/transport/lib/transport_web/router.ex` where they are defined
* Check-out `apps/transport/lib/transport_web/plugs/router.ex` (`/api`, `/gbfs` & the rest)
  * This top-level router is referred to in `apps/transport/lib/transport_web/endpoint.ex`
* Run `mix phx.routes TransportWeb.API.Router` (this will list all the `/api` sub-routes)
* Run `mix phx.routes GBFS.Router` (same for `/gbfs`)
* **In short**: the "endpoint" includes a main router, which in turn includes 3 sub-routers

### Read the logs from the database

* Install [`clever-tools`](https://github.com/CleverCloud/clever-tools)
* `clever login`
* `clever --help`
* Go to your local `transport-site` git clone
* `clever link $$REPLACE_BY_APP_ID$$` (pick `app_id` in the CleverCloud dashboard for `transport-site`)
* `clever status`
* `clever logs --help`
* `clever logs` to stream the current logs
* `clever logs --addon $$REPLACE_BY_PG_ADDON_ID$$` (pick addon_id at top-right of CC dashboard for `transport-site-postgresql` "Information" tab)

### Learn how to deploy the Elixir app on staging (aka "prochainement")

* Use a force push of your branch, e.g. `git push <remote> <branche>:prochainement -f` (so if your branch is `some-feature`, this will usually be: `git push origin some-feature:prochainement -f`)
* This will trigger a redeploy
* If you see errors in the CC app logs due to Ecto migrations (due to divergence of branches), you'll want to reset the staging database (see below)

### Learn how to reset the staging (aka "prochainement") database

* Go to the CleverCloud dashboard for the production Postgres database and download it locally
* Read the [restore_db.sh](https://github.com/etalab/transport-site/blob/master/restore_db.sh) script
* Go to the CleverCloud dashboard for the **staging** Postgres database, and run `restore_db.sh` with proper parameters

### Learn how to connect via SSH

* Make sure to link the correct app (production or staging) with `clever link $$REPLACE_BY_APP_ID$$` (as displayed in the staging/production app CC dashboards)
* Verify the linking status with `clever applications`
* Log with the app alias: `clever ssh --alias transport-prochainement`

### Explore the GBFS conversion proxy

* Check out the code under `apps/gbfs`
* Run the app locally with `mix phx.server`
* Discover the available converted feeds via `http://localhost:5000/gbfs`
* Note that this does not contain all the GBFS feeds, only the ones we convert

### Learn about the GTFS and GTFS-RT specifications

* @thbar bought https://gumroad.com/l/gtfsbundle (available to the team on demand)
* Download a tiny GTFS ([example](https://transport.data.gouv.fr/datasets/horaires-theoriques-et-temps-reel-des-navettes-de-la-station-de-tignes-gtfs-gtfs-rt/))
* Check out this [diagram](https://www.researchgate.net/figure/Modele-de-donnees-GTFS_fig7_268333353)
* Read the GTFS guide
* Read the GTFS-realtime guide

### Explore the GTFS validator locally

* Clone the [transport-validator](https://github.com/etalab/transport-validator) project locally
* Install Rust
* Install [Rust Analyzer](https://github.com/rust-analyzer/rust-analyzer) for VSCode completion
* Run all the tests with `cargo run test`

### Run the GTFS validator via the Elixir app locally

* Compile the validator project with `cargo build --release`
* Run it as a server with `./target/release/main`
* Use the displayed host & port (e.g. `http://127.0.0.1:7878`) to fill your `.envrc` configuration (`export GTFS_VALIDATOR_URL=http://127.0.0.1:7878`)
* Run the site with `mix phx.server`
* Go to `http://localhost:5000/validate`
* Upload a GTFS file
* Verify that it goes through the Elixir apps logs, then the validator logs

### Debug the GTFS validator locally

* Make sure to have Rust Analyzer installed
* Install the [CodeLLDB extension](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) to help with debugging
* Run "Debug unit tests in library 'validator'"
* Add a breakpoint and verify that it is effective
* Read [this article](https://khalid-salad.medium.com/plp-rust-agjks-395d1d870432) for more information

### Run the realtime API locally

* Clone the [transpo-rt](https://github.com/etalab/transpo-rt) project locally
* TODO

### IDEAS for the next steps

* Understanding the code behind https://github.com/etalab/transport-site/pull/1373
* Overall architecture (diagram by Francis)
* Structure of the Umbrella app (apps)
* Measuring code coverage
* Discovering the database structure
* Clever Cloud deployment and operations (Sentry, UptimeRobot)
* Running import jobs (locally)
* Diving into import jobs (locally)
* What is GBFS (workshop, slides)
* How to upgrade Elixir, Erlang and Node
* How to launch linters etc (like CI does)
