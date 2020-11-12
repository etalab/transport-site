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

### IDEAS for the next steps

* Overall architecture (diagram by Francis)
* Structure of the Umbrella app (apps)
* Measuring code coverage
* Discovering the HTTP routes
* Discovering the database structure
* Clever Cloud deployment and operations (Sentry, UptimeRobot)
* Deploy on "prochainement"
* Investigate data quality from the stats map
* Running and testing the validator (locally)
* Running import jobs (locally)
* Diving into import jobs (locally)
* How GBFS works
* How to upgrade Elixir, Erlang and Node
