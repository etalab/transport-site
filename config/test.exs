use Mix.Config

alias Datagouvfr.Authentication

# avoid test failures with VCR, as tzdata tries to update
config :tzdata, :autoupdate, :disabled

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :transport, TransportWeb.Endpoint,
  http: [port: 5001],
  server: true

# Page cache would make tests brittle, so disable it by default
config :gbfs, :disable_page_cache, true

# Override cache implementation
config :transport, cache_impl: Transport.Cache.Null

# Override ExAws (S3...) implementation
config :transport, ex_aws_impl: Transport.ExAWS.Mock

config :transport, httpoison_impl: Transport.HTTPoison.Mock

# capture all info logs and up during tests
config :logger, level: :info

# ... but show only warnings and up on the console
config :logger, :console,
  level: :warn

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
