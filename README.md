# Transport

## Installation

  * Make sure you have **Elixir**, **Node**, **Yarn** and **PhantomJS** installed and up-to-date
  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `mix yarn install`

In order to validate datasets:

  * Make sure you have [**gtfs-validator**](https://github.com/etalab/transport-validator) installed and up-to-date
  * Set the environment variable `GTFS_VALIDATOR_URL` to your datatools running instance URL.

## Usage

  * Run the server with `mix phx.server`
  * Run the webdriver server with `phantomjs --wd`
  * Run the tests with `mix test`
  * Run the integration tests with `mix test --only integration`
  * Run the solution tests with `mix test --only solution`
  * Run the external tests with `mix test --only external`
  * Run the elixir linter with `mix credo --strict`
  * Run the javascript linter with `mix npm "run linter:ecma"`
  * Run the sass linter with `mix npm "run linter:sass"`

Now you can visit [`127.0.0.1:5000`](http://127.0.0.1:5000) from your browser.

## Docker

### Production

  The Dockerfile needed to run the continuous integration is in the project:
  https://github.com/etalab/transport-ops

  Update it if needed (e.g. updating Elixir’s version) and then update `.circleci/config.yml`.

### Development

  You can use docker-compose to develop on this project
  You need a .env file with the same variables that you have in .envrc.example (but you'll need to remove `export` at the beginning of each line.
  In this file as PG_URL use `PG_URL=ecto://postgres:example@database/transport_repo`

  To install elixir dependencies run these commands:

  - `docker-compose run web mix deps.get`
  - `docker-compose run web mix deps.compile`

  Install yarn:
  `docker-compose run web mix yarn install`

  If you have access to a database file you can run this command to restore the database:
  `docker-compose run web ./restore_db.sh name_of_the_file`
  _the file needs to be in this directory_

  If you don't have access to such file run
  - `docker-compose run web mix ecto.create`
  - `docker-compose run web mix ecto.migrate`

  You can now start the application with:
  `docker-compose up`

  And access it at http://localhost:5000

