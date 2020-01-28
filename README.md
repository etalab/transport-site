# Transport

This is the repository of the french National Access Point (NAP) for mobility data.

This project brings a mobility focus on data hosted on [data.gouv.fr](https://www.data.gouv.fr), the french open data portal.

# Installation

You can install this 2 different ways:
* [manually](#manual_install), this is the best way to install it if you plan to work often on the project.
* [with docker](#docker_install), this is an easier installation process at the cost of a slightly more cumbersome development workflow.

## Manual installation <a name="manual_install"></a>

  * Make sure you have **Elixir**, **Node**, **Yarn** and **Docker** installed and up-to-date
    * **Elixir** is often installed with [asdf](https://asdf-vm.com/) since it makes it easy to handle different **Elixir** versions accross projects. The project needx at least **Elixir** 1.8 and **Erlang** 21.0
  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `mix yarn install`

### Postgresql

You also need an up to date postgresql with postgis installed.

## Configuration

For easier configuration handling you can use [direnv](https://direnv.net/).

* copy the example file `cp .envrc.example .envrc`;
* in the terminal, generate a phoenix secret key with the command `mix phx.gen.secret` and paste the result in the .envrc file at the line `export SECRET_KEY_BASE=<secret_key>`
* you must know the password of the postgres user, and update the `PG_URL` environment variable accordingly : `export PG_URL=ecto://postgres:<postgres_user_password>@localhost/transport_repo`
* by default, connections to postgresql will be made on the 5432 port. If your postgresql installation uses a different port, or if you have several postgresql installed, update the `PG_URL` environment variable accordingly :
`export PG_URL=ecto://postgres:postgres@localhost:<port>/transport_repo`

* allow direnv to export those variables `direnv allow .`


#### Creating a database

Create the database with the command `mix ecto.create`.

Alternatively, you can create it manually. With the permission to create a database (on Debian based system, you need to be logged as `postgres`), type
`createdb transport_repo`.

#### Applying the migrations

To have an up to date database schema run `mix ecto.migrate`.

#### Restoring the production database

The production database does not contains any sensitive data, you can retreive it for dev purpose.
* You can retreive the [latest clever-cloud backup](https://console.clever-cloud.com/organisations/orga_f33ebcbc-4403-4e4c-82f5-12305e0ecb1b/addons/addon_beebaa5e-c3a4-4c57-b124-cf9d1473450a) (you need some permissions to access it, if you don't have them, you can ask someone on the team to give you the database)
* On the clever-cloud website, under transport-site-postgresql, there is a Backups section with download links.
* restore the downloaded backup on you database: `./restore_db.sh <path_to_the_backup>`


## Usage

Run the server with `mix phx.server` and you can visit [`127.0.0.1:5000`](http://127.0.0.1:5000) on your browser.

## Development

### Testing

Before running the integration tests, you need to start a selenium web driver with `docker run -p 4444:4444 --network=host selenium/standalone-chrome:3.141.59-oxygen`

Run the tests with `MIX_ENV=test mix test`

You can also:

  * Run the integration tests with `MIX_ENV=test mix test --only integration`
  * Run the solution tests with `MIX_ENV=test mix test --only solution`
  * Run the external tests with `MIX_ENV=test mix test --only external`

### Linting

  * Run the elixir linter with `mix credo --strict`
  * Run the javascript linter with `mix npm "run linter:ecma"`
  * Run the sass linter with `mix npm "run linter:sass"`

### Misc Elixir command

#### Translations

To extract all translations from the source, you can run `mix gettext.extract --merge` (and then edit the modified .po files).

#### DB migrations

To generate a new migration file:
`cd apps/db && mix ecto.gen.migration <name of the migration> && cd ..`

The generated [ecto](https://hexdocs.pm/ecto/Ecto.html) migration file will be `apps/db/priv/repo/migrations/<timestamp>_<name of the migration>.exs`

To apply all migrations on you database:
`mix ecto.migrate`


## Docker installation <a name="docker_install"></a>

### Development

If you don't plan to work a lot on this project, the docker installation is way easier.

You need a .env file with the same variables that you have in .envrc.example (but you'll need to remove `export` at the beginning of each line.
(No need to setup the variable `PG_URL`, it is defined in the docker-compose.yml)

Then you only need to run:
  `docker-compose up`

And access it at http://localhost:5000

You can make changes in the repository and those will be applied with hot reload.

You can run any `mix` command with:

`docker-compose run web mix <cmd>`

For the tests you also need to add an environment variable:

`docker-compose run -e MIX_ENV=test web mix test`

### Production

  The Dockerfile needed to run the continuous integration is in the project:
  https://github.com/etalab/transport-ops

  Update it if needed (e.g. updating Elixir’s version) and then update `.circleci/config.yml`.
