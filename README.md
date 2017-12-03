# Transport

### Installation

  * Make sure you have **Elixir**, **Node**, **Yarn** and **PhantomJS** installed and up-to-date
  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `mix yarn install`

### Usage

  * Run the server with `mix phx.server`
  * Run the webdriver server with `phantomjs --wd`
  * Run the tests with `mix test`
  * Run the integration tests with `mix test --only integration`
  * Run the elixir linter with `mix credo --strict`
  * Run the javascript linter with `mix npm "run linter:ecma"`
  * Run the riot linter with `mix npm "run linter:riot"`
  * Run the sass linter with `mix npm "run linter:sass"`

Now you can visit [`127.0.0.1:5000`](http://127.0.0.1:5000) from your browser.

### Tasks

  * Run `mix transport.seed` to seed datasets to the database.
  * Run `mix transport.reset` to delete datasets from the database.
  * Run `mix transport.validate_data` to queue dataset validations.

### Docker

  After having made your changes:

  * `docker build . -t username/transport:x.y.z`
  * `docker push username/transport:x.y.z`

  And then update `.circleci/config.yml`.
