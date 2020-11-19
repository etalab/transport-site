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

* Ask the team how to fill `.envrc` for minimal use (we'll remove the need for that in the future)
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

### Run the GTFS validator locally

### IDEAS for the next steps

* Understanding the code behind https://github.com/etalab/transport-site/pull/1373
* Overall architecture (diagram by Francis)
* Structure of the Umbrella app (apps)
* Measuring code coverage
* Discovering the HTTP routes
* Discovering the database structure
* Clever Cloud deployment and operations (Sentry, UptimeRobot)
* Deploy on "prochainement"
* Investigate data quality from the stats map
* Running import jobs (locally)
* Diving into import jobs (locally)
* What is GBFS (workshop, slides)
* How GBFS is handled in this app
* How to upgrade Elixir, Erlang and Node
* How to launch linters etc (like CI does)
