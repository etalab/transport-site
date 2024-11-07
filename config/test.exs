import Config

alias Datagouvfr.Authentication

# avoid test failures with VCR, as tzdata tries to update
config :tzdata, :autoupdate, :disabled

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :transport, TransportWeb.Endpoint,
  # If you change this, there are hardcoded refs in the source to update
  http: [port: 5100],
  server: true

config :oauth2, adapter: Tesla.Mock

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
  req_impl: Transport.Req.Mock,
  history_impl: Transport.History.Fetcher.Mock,
  gtfs_validator: Shared.Validation.Validator.Mock,
  gbfs_validator_impl: Shared.Validation.GBFSValidator.Mock,
  rambo_impl: Transport.Rambo.Mock,
  gbfs_metadata_impl: Transport.Shared.GBFSMetadata.Mock,
  availability_checker_impl: Transport.AvailabilityChecker.Mock,
  jsonschema_validator_impl: Shared.Validation.JSONSchemaValidator.Mock,
  tableschema_validator_impl: Shared.Validation.TableSchemaValidator.Mock,
  schemas_impl: Transport.Shared.Schemas.Mock,
  hasher_impl: Hasher.Mock,
  validator_selection: Transport.ValidatorsSelection.Mock,
  data_visualization: Transport.DataVisualization.Mock,
  unzip_s3_impl: Transport.Unzip.S3.Mock,
  siri_query_generator_impl: Transport.SIRIQueryGenerator.Mock,
  s3_buckets: %{
    history: "resource-history-test",
    on_demand_validation: "on-demand-validation-test",
    gtfs_diff: "gtfs-diff-test",
    logos: "logos-test"
  },
  workflow_notifier: Transport.Jobs.Workflow.ProcessNotifier,
  export_secret_key: "fake_export_secret_key",
  api_auth_clients: "client1:secret_token;client2:other_token",
  enroute_token: "fake_enroute_token",
  enroute_validation_token: "fake_enroute_token",
  enroute_validator_client: Transport.EnRouteChouetteValidClient.Mock,
  netex_validator: Transport.Validators.NeTEx.Mock

config :ex_aws,
  cellar_organisation_id: "fake-cellar_organisation_id"

config :ex_aws, :database_backup_source, bucket_name: "fake_source_bucket_name"

config :ex_aws, :database_backup_destination, bucket_name: "fake_destination_bucket_name"

config :datagouvfr,
  community_resources_impl: Datagouvfr.Client.CommunityResources.Mock,
  authentication_impl: Datagouvfr.Authentication.Mock,
  user_impl: Datagouvfr.Client.User.Mock,
  datagouvfr_reuses: Datagouvfr.Client.Reuses.Mock,
  datagouvfr_discussions: Datagouvfr.Client.Discussions.Mock,
  organization_impl: Datagouvfr.Client.Organization.Mock,
  # The two following implementations are often overriden with Mox.stubs_with/2 in tests
  # Because legacy tests mock at a lower level (HTTPoison), we need to keep the same behavior for now
  datasets_impl: Datagouvfr.Client.Datasets.Mock,
  resources_impl: Datagouvfr.Client.Resources.Mock

# capture all info logs and up during tests
config :logger, level: :debug

# ... but show only warnings and up on the console
config :logger, :console, level: :warning

# Configure data.gouv.fr authentication
config :oauth2, Authentication,
  site: "https://demo.data.gouv.fr",
  client_id: "my_client_id",
  client_secret: "my_client_secret"

# Validator configuration
config :transport, gtfs_validator_url: System.get_env("GTFS_VALIDATOR_URL") || "http://127.0.0.1:7878"

config :exvcr,
  vcr_cassette_library_dir: "test/fixture/cassettes",
  filter_request_headers: ["authorization"]

config :transport, DB.Repo,
  url:
    System.get_env("PG_URL_TEST") || System.get_env("PG_URL") ||
      "ecto://postgres:postgres@localhost/transport_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  # https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config
  # fix for https://github.com/etalab/transport-site/issues/2539
  queue_target: 5000

config :transport,
  datagouvfr_site: "https://demo.data.gouv.fr",
  datagouvfr_apikey: "fake-datagouv-api-key",
  # NOTE: some tests still rely on ExVCR cassettes at the moment. We configure the
  # expected host here, until we move to a behaviour-based testing instead.
  gtfs_validator_url: "https://validation.transport.data.gouv.fr",
  consolidation: %{
    zfe: %{
      dataset_id: "zfe_fake_dataset_id",
      resource_ids: %{
        "voies" => "zfe_voies_fake_resource_id",
        "aires" => "zfe_aires_fake_resource_id"
      }
    },
    bnlc: %{
      dataset_id: "bnlc_fake_dataset_id",
      resource_id: "bnlc_fake_resource_id"
    },
    irve: %{
      resource_id: "eb76d20a-8501-400e-b336-d85724de5435"
    }
  }

secret_key_base = "SOME-LONG-SECRET-KEY-BASE-FOR-TESTING-SOME-LONG-SECRET-KEY-BASE-FOR-TESTING"

config :transport, TransportWeb.Endpoint,
  secret_key_base: secret_key_base,
  live_view: [
    # NOTE: unsure if this is actually great to reuse the same value
    signing_salt: secret_key_base
  ]

config :phoenix_ddos,
  blocklist_ips: ["1.2.3.4"]

# The Swoosh test adapter works a bit like an embryo of Mox.
# See: https://github.com/swoosh/swoosh/blob/main/lib/swoosh/adapters/test.ex
#
# It won't be as flexible in all situations (see https://github.com/swoosh/swoosh/issues/66).
#
# If this causes issues, we will have instead to create
# a behaviour/wrapper around `Transport.Mailer`
config :transport, Transport.Mailer, adapter: Swoosh.Adapters.Test

# avoid logging
config :os_mon,
  start_memsup: false

# See https://hexdocs.pm/sentry/Sentry.Test.html
config :sentry, test_mode: true
