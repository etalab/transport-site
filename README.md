# Transport

Installation:

  * Make sure you have **Elixir**, **Node**, **Yarn** and **PhantomJS** installed and up-to-date
  * Install Elixir dependencies with `mix deps.get`
  * Install Node.js dependencies with `mix yarn install`
  * Install Elm dependencies with `mix elm install`
  * Optional: install linters with

    ```
    npm install -g elm \
                   eslint \
                   eslint-config-standard \
                   eslint-plugin-import \
                   eslint-plugin-node \
                   eslint-plugin-promise \
                   eslint-plugin-standard \
                   sass-lint
    ```

Usage:

  * Run the up with `mix phx.server`
  * Run the tests with `mix test` and `mix elm test` (you need to have `phantomjs --wd` running)
  * Run the elixir linter with `mix credo --strict`
  * Run the javascript linter with `eslint -c .eslintrc client`
  * Run the sass linter with `sass-lint -c .sass-lint.yml  -v -q`

Now you can visit [`127.0.0.1:5000`](http://127.0.0.1:5000) from your browser.
