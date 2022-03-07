# Transport

This is the repository of the [french National Access Point](https://transport.data.gouv.fr/) (NAP) for mobility data.

This project brings a mobility focus on data hosted on [data.gouv.fr](https://www.data.gouv.fr), the french open data portal.

You will find user documentation at [doc.transport.data.gouv.fr](https://doc.transport.data.gouv.fr).

A status dashboard is available at [https://stats.uptimerobot.com/q7nqyiO9yQ](https://stats.uptimerobot.com/q7nqyiO9yQ) for a part of the project.

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

Installation can then be done with:
* `asdf install`

### Postgresql

You also need an up to date postgresql with postgis installed. Version 12+ is recommended.

For Mac users, you can use https://postgresapp.com/.

#### Dependencies

Download depencies using `mix deps.get`.

Reply "Yes" to the question "Shall I install Hex? (if running non-interactively, use "mix local.hex --force")".

#### Creating a database

Create the database with the command `mix ecto.create`.

Alternatively, you can create it manually. With the permission to create a database (on Debian based system, you need to be logged as `postgres`), type
`createdb transport_repo`.

#### Applying the migrations

To have an up to date database schema run `mix ecto.migrate`.

#### Restoring the production database

The production database does not contains any sensitive data, you can retreive it for dev purpose.
* You can retrieve the [latest clever-cloud backup](https://console.clever-cloud.com/organisations/orga_f33ebcbc-4403-4e4c-82f5-12305e0ecb1b/addons/addon_beebaa5e-c3a4-4c57-b124-cf9d1473450a) (you need some permissions to access it, if you don't have them, you can ask someone on the team to give you the database)
* On the clever-cloud website, under transport-site-postgresql, there is a Backups section with download links.
* restore the downloaded backup on you database: `./restore_db.sh <path_to_the_backup>`

#### Binary CLI dependencies

The app uses a number of tools via [transport-tools](https://github.com/etalab/transport-tools).

They are expected at `./transport-tools` by default (but this can be configured via `:transport_tools_folder` in `config.exs`).

When working locally, you may want to have these tools readily available at times.

```
mkdir transport-tools
cd transport-tools

# jars are cross-platform, so we can copy them from the container (see `transport-tools` repository for exact naming)
docker run --rm -v $(pwd):/binary ghcr.io/etalab/transport-tools:latest /bin/sh -c "cp /usr/local/bin/*.jar /binary"
```

For Rust binaries, you will have to compile them locally and copy them to the same folder.

Once this is done, make sure to configure your configuration via `:transport_tools_folder`.

## Usage

Run the server with `mix phx.server` and you can visit [`127.0.0.1:5000`](http://127.0.0.1:5000) on your browser.

## Usage of the Elixir Proxy

[`apps/unlock`](https://github.com/etalab/transport-site/tree/master/apps/unlock) is a sub-part of the "umbrella app", which is served on its own subdomain (https://proxy.transport.data.gouv.fr for production, https://proxy.prochainement.transport.data.gouv.fr/ for staging).

The proxy relies on this [yaml configuration](https://github.com/etalab/transport-proxy-config/blob/master/proxy-config.yml) which is currently fetched at runtime once (but can be hot-reloaded via this [backoffice page](https://transport.data.gouv.fr/backoffice/proxy-config)).

Each proxied "feed" (currently GTFS-RT data) has a private (target) url hidden from the general public, can be configured with an independent Time-To-Live (TTL), and is exposed as a credential-free public url to the public. When a query occurs, the incoming HTTP connection is kept on hold while the proxy issues a query to the target server, caching the response in RAM based on the configured TTL.

The backoffice implementation leverages [LiveView](https://github.com/phoenixframework/phoenix_live_view) to provide an automatically updated dashboard view with all the feeds, the size of the latest payload, the latest HTTP code returned by the target etc. Implementation is [here](https://github.com/etalab/transport-site/tree/master/apps/transport/lib/transport_web/live/backoffice).

When working in development, instead of fetching the configuration from GitHub, the configuration is taken from a local config file (`config/proxy-config.yml`, see [config](https://github.com/etalab/transport-site/blob/master/config/dev.exs#L3)), in order to make it very easy to play with sample configurations locally.

For local work, you will have (for now at least) to add `proxy.localhost 127.0.0.1` to your `/etc/hosts` file.

The app currently routes whatever starts with `proxy.` to the proxy (as implemented [here](https://github.com/etalab/transport-site/blob/master/apps/transport/lib/transport_web/plugs/router.ex)), although in the future we will probably use a more explicit configuration.

## Development

### Testing

#### Running the tests

Run the tests with `mix test`

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

#### Measuring test coverage

We use [excoveralls](https://github.com/parroty/excoveralls) to measure which parts of the code are covered by testing (or not). This is useful to determine where we can improve the testing quality.

The following commands will launch the test and generate coverage:

```
# Display overall (whole app) coverage for all tests in the console
MIX_ENV=test mix coveralls --umbrella
# Same with a HTML report
MIX_ENV=test mix coveralls.html --umbrella

# Display coverage for each umbrella component, rather
MIX_ENV=test mix coveralls
```

The coverage is written on screen by default, or in the `cover` subfolders for HTML output.

Running in `--umbrella` mode will generate coverage report at the top-level `cover` folder, while running without it will generate reports under each umbrella sub-app (e.g. `apps/db/cover`).

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

#### One shot tasks

Some custom one shot tasks are available.

To run a custom task: `mix <custom task>`

* `Transport.ImportAom`: import the aom data from the cerema
* `Transport.ImportEPCI`: import the french EPCI from data.gouv
* `Transport.OpenApiSpec`: generate an OpenAPI specification file

## Docker installation <a name="docker_install"></a>

### Development

If you don't plan to work a lot on this project, the docker installation is way easier.

You need a .env file, and can use .env.example to see which variables need to be set.
(No need to setup the variable `PG_URL`, it is defined in the docker-compose.yml)

Then you only need to run:
  `docker-compose up`

And access it at http://localhost:5000

You can make changes in the repository and those will be applied with hot reload.

You can run any `mix` command with:

`docker-compose run web mix <cmd>`

For the tests you also need to add an environment variable:

`docker-compose run -e web mix test`

### Production

  The Dockerfile needed to run the continuous integration is in the project:
  https://github.com/etalab/transport-ops

  Update it if needed (e.g. updating Elixir’s version) and then update `.circleci/config.yml`.

### Domain names

The following domain names are currently in use by the deployed Elixir app:

* Production
  * site: https://transport.data.gouv.fr
  * jobs: https://workers.transport.data.gouv.fr
  * proxy: https://proxy.transport.data.gouv.fr
* Staging
  * site: https://prochainement.transport.data.gouv.fr
  * jobs: https://workers.prochainement.transport.data.gouv.fr
  * proxy: https://proxy.prochainement.transport.gouv.fr

These names are [configured via a CNAME on CleverCloud](https://www.clever-cloud.com/doc/administrate/domain-names/#using-personal-domain-names).

The corresponding SSL certificates are auto-generated via Let's Encrypt and CleverCloud.

# Blog
The project [blog](https://blog.transport.data.gouv.fr/) code and articles are hosted in the [blog](https://github.com/etalab/transport-site/tree/blog/blog) folder of the blog branch. A specific blog branch has been created with less restrictive merge rules, to allow publishing articles directly from the CMS without needing a github code review.

Technically, the blog is a hugo static website, enhanced with [netlifyCMS](https://www.netlifycms.org/) that is automatically deployed using Netlify. NetlifyCMS allows github users who have write access to this repo to write and edit articles, without the need to use git nor github.

To write or edit an article, visit https://blog.transport.data.gouv.fr/admin/.

For developement purposes, you can run the blog locally. Install [hugo](https://gohugo.io/getting-started/installing/), open a terminal, go the blog folder of the project and run `hugo serve`.

# Troubleshootings

## No usable OpenSSL found (during Erlang installation via ASDF)
MacOS come with a pre-installed version of LibreSSL which is a fork from OpenSSL.
This could cause trouble since it's considered as a "no usable OpenSSL" by Erlang.

We can fix this error in 2 steps :
1. Install OpenSSL 1.1 (via homebrew for example)
```
> brew install --prefix=openssl
```
2. Force the use of the installed version when installing erlang by setting the --with-ssl option in the KERL_CONFIGURE_OPTIONS variable.
```
> export KERL_CONFIGURE_OPTIONS="--with-ssl=$(brew --prefix --installed openssl@1.1)"
> asdf install erlang 24.0.4
```
See https://github.com/asdf-vm/asdf-erlang/issues/82.
