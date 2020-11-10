# Transport

This is the repository of the [french National Access Point](https://transport.data.gouv.fr/) (NAP) for mobility data.

This project brings a mobility focus on data hosted on [data.gouv.fr](https://www.data.gouv.fr), the french open data portal.

You will find user documentation at [doc.transport.data.gouv.fr](https://doc.transport.data.gouv.fr).

A status dashboard is available at [https://status.transport.data.gouv.fr](https://status.transport.data.gouv.fr) for a part of the project.

# Glossary

A small glossary explaining the various terms can be found in this repo ([glossary.md](glossary.md)). Please feel free to add any term which appears initially foreign there.

# Installation

You can install this 2 different ways:
* [manually](#manual_install), this is the best way to install it if you plan to work often on the project.
* [with docker](#docker_install), this is an easier installation process at the cost of a slightly more cumbersome development workflow.

## Manual installation <a name="manual_install"></a>

  * Make sure you have **Elixir**, **Node**, **Yarn** and **Docker** installed and up-to-date
    * **Elixir** is often installed with [asdf](https://asdf-vm.com/) since it makes it easy to handle different **Elixir** versions accross projects. The project needs at least **Elixir** 1.8 and **Erlang** 21.0
  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `mix yarn install`

If you wish to use `asdf` (recommended), make sure to install the correct plugins:

* `asdf plugin-add erlang` (https://github.com/asdf-vm/asdf-erlang)
* `asdf plugin-add elixir` (https://github.com/asdf-vm/asdf-elixir)
* `asdf plugin-add nodejs` (https://github.com/asdf-vm/asdf-nodejs)
* Make sure to add the [OpenPGP keys](https://github.com/asdf-vm/asdf-nodejs#install) for the nodejs plugin

Installation can then be done with:
* `asdf install`

### Postgresql

You also need an up to date postgresql with postgis installed. Version 12+ is recommended.

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

#### Selenium web driver

Before running the `integration` or `solution` tests, you need to start a selenium web driver.

On Linux, you can do this with `docker run -p 4444:4444 --network=host selenium/standalone-chrome:3.141.59-oxygen`.

On Mac, the situation is currently a bit more complicated. Docker network host won't currently work there, but you can instead install and start ChromeDriver like this:

```
# https://github.com/HashNuke/hound/wiki/Starting-a-webdriver-server#starting-a-chromedriver-server
brew cask install chromedriver
chromedriver --port=4444 --url-base=wd/hub
```

Expect different behaviour with this method, because the version of ChromeDriver won't be necessarily the same.

#### Running the tests

Run the tests with `MIX_ENV=test mix test`

You can also:

  * Run the integration tests with `MIX_ENV=test mix test --only integration`
  * Run the solution tests with `MIX_ENV=test mix test --only solution`
  * Run the external tests with `MIX_ENV=test mix test --only external`
  * Run everything with `MIX_ENV=test RUN_ALL=1 mix test`

The application is an [umbrella app](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html). It means that it is split into several sub-projects (that you can see under `/apps`).

To run tests for a specific app, for example the `transport` or `gbfs` app, use this command:

```
# for apps/transport app
mix cmd --app transport mix test --color
# for apps/gbfs
mix cmd --app gbfs mix test --color

# or, for a single file, or single test
mix cmd --app transport mix test --color test/transport_web/integrations/backoffice_test.exs 
mix cmd --app transport mix test --color test/transport_web/integrations/backoffice_test.exs:8
```

The filenames must be relative to the app folder. This [will be improved](https://dockyard.com/blog/2019/06/17/testing-in-umbrella-apps-improves-in-elixir-1-9) when we upgrade to a more modern Elixir version.

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
  
# Blog
The project [blog](https://blog.transport.data.gouv.fr/) code and articles are hosted in the [blog](https://github.com/etalab/transport-site/tree/blog/blog) folder of the blog branch. A specific blog branch has been created with less restrictive merge rules, to allow publishing articles directly from the CMS without needing a github code review.

Technically, the blog is a hugo static website, enhanced with [netlifyCMS](https://www.netlifycms.org/) that is automatically deployed using Netlify. NetlifyCMS allows github users who have write access to this repo to write and edit articles, without the need to use git nor github.

To write or edit an article, visit https://blog.transport.data.gouv.fr/admin/.

For developement purposes, you can run the blog locally. Install [hugo](https://gohugo.io/getting-started/installing/), open a terminal, go the blog folder of the project and run `hugo serve`.
