use Mix.Config

alias Datagouvfr.Authentication

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :transport, TransportWeb.Endpoint,
  http: [port: 5001],
  server: true

# Page cache would make tests brittle, so disable it by default
config :gbfs, :disable_page_cache, true

# Override cache implementation
config :transport, cache_impl: Transport.Cache.Mock

# Integration testing with Hound
# See docs at:
# * https://github.com/HashNuke/hound/blob/master/notes/configuring-hound.md
# * https://github.com/HashNuke/hound/wiki/Starting-a-webdriver-server
config :hound, driver: "selenium", browser: "chrome"

# Print only warnings and errors during test
config :logger, level: :warn

# Configure data.gouv.fr authentication
config :oauth2, Authentication,
  site: "https://demo.data.gouv.fr"

# Validator configuration
config :transport, gtfs_validator_url: System.get_env("GTFS_VALIDATOR_URL") || "http://127.0.0.1:7878"

config :exvcr, [
  vcr_cassette_library_dir: "test/fixture/cassettes",
  filter_request_headers: ["authorization"]
]

config :db, DB.Repo,
  url: System.get_env("PG_URL_TEST") || System.get_env("PG_URL") || "ecto://postgres:postgres@localhost/transport_test",
  pool: Ecto.Adapters.SQL.Sandbox
