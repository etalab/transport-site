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

config :unlock,
  config_fetcher: Unlock.Config.Fetcher.Mock,
  http_client: Unlock.HTTP.Client.Mock,
  # Used for config testing
  github_config_url: "https://localhost/some-github-url",
  github_auth_token: "some-test-github-auth-token"

# Use stubbing to enjoy disconnected tests & allow setting mocks expectations
config :transport,
  cache_impl: Transport.Cache.Null,
  ex_aws_impl: Transport.ExAWS.Mock,
  httpoison_impl: Transport.HTTPoison.Mock,
  history_impl: Transport.History.Fetcher.Mock

config :datagouvfr,
  community_resources_impl: Datagouvfr.Client.CommunityResources.Mock

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

# temporary stuff, yet this is not DRY
config :transport,
  datagouvfr_site: "https://demo.data.gouv.fr",
  # NOTE: the tests are normally expected to be marked :external
  # and rely on ExVCR cassettes at the moment. This provides the expected
  # target host name for them, until we move to a behaviour-based testing instead.
  gtfs_validator_url: "https://transport-validator.cleverapps.io"

config :transport, TransportWeb.Endpoint,
  secret_key_base: "SOME-LONG-SECRET-KEY-BASE-FOR-TESTING-SOME-LONG-SECRET-KEY-BASE-FOR-TESTING"
