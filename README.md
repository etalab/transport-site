# Transport

### Installation

  * Make sure you have **Elixir**, **Node**, **Yarn** and **PhantomJS** installed and up-to-date
  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `mix yarn install`

In order to validate datasets:

  * Make sure you have [**gtfs-validator**](https://github.com/etalab/transport-validator) installed and up-to-date
  * Set the environment variable `GTFS_VALIDATOR_URL` to your datatools running instance URL.

### Usage

  * Run the server with `mix phx.server`
  * Run the webdriver server with `phantomjs --wd`
  * Run the tests with `mix test`
  * Run the integration tests with `mix test --only integration`
  * Run the solution tests with `mix test --only solution`
  * Run the external tests with `mix test --only external`
  * Run the elixir linter with `mix credo --strict`
  * Run the javascript linter with `mix npm "run linter:ecma"`
  * Run the riot linter with `mix npm "run linter:riot"`
  * Run the sass linter with `mix npm "run linter:sass"`

Now you can visit [`127.0.0.1:5000`](http://127.0.0.1:5000) from your browser.

### Managing the data

To populate the mongo database

  * Download the latest dump from the production
  * Run `mongorestore --gzip --archive=downloaded_dump.archive.gz`
  * To validate the datasets, run `mix transport.simple_validation`

### Docker

  The Dockerfile needed to run the continuous integration is in the project:
  https://github.com/etalab/transport-ops

  Update it if needed (e.g. updating Elixir’s version) and then update `.circleci/config.yml`.
