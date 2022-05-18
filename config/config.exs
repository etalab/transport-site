# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# NOTE: this is very much legacy & work in progress to modernize the situation.
# For reference, ultimately most tests should not connect to outside stuff.
# A good model for improvements is https://github.com/hexpm/hexpm/tree/main/config
#
import Config

config :unlock,
  config_fetcher: Unlock.Config.GitHub,
  http_client: Unlock.HTTP.FinchImpl,
  github_config_url: "https://raw.githubusercontent.com/etalab/transport-proxy-config/master/proxy-config.yml",
  github_auth_token: System.get_env("TRANSPORT_PROXY_CONFIG_GITHUB_TOKEN")

# NOTE: the config is unused by the app (because the endpoint is not used, the
# unlock router is directly wired into the main transport endpoint). The config key
# is nonetheless present to avoid a warning at runtime / test time.
config :unlock, Unlock.Endpoint, []

if System.get_env("CELLAR_NAMESPACE") do
  # We believe CELLAR_NAMESPACE was a previous attempt at siloting S3 envs.
  # We will instead rely on separate buckets in the short-term future.
  raise "CELLAR_NAMESPACE variable is deprecated and must be removed."
end

config :gbfs,
  generators: [context_app: false]

config :gbfs, jcdecaux_apikey: System.get_env("JCDECAUX_APIKEY")

# Configures the endpoint
config :gbfs, GBFS.Endpoint,
  render_errors: [view: GBFS.ErrorView, accepts: ~w(json)],
  # TODO: verify if this is truly needed? unsure.
  pubsub_server: GBFS.PubSub,
  server: false

# Configures the endpoint
config :transport, TransportWeb.Endpoint,
  url: [host: "127.0.0.1"],
  render_errors: [
    view: TransportWeb.ErrorView,
    layout: {TransportWeb.LayoutView, "app.html"},
    accepts: ~w(html json)
  ],
  pubsub_server: TransportWeb.PubSub

config :phoenix, :json_library, Jason

#
# A tweaked format encoder to optionally bypass JSON
# encoding when the caller knows it is already encoded.
#
# See https://hexdocs.pm/phoenix/1.5.8/Phoenix.Template.html#module-format-encoders
#
config :phoenix, :format_encoders, json: Transport.Shared.ConditionalJSONEncoder

# Configures Elixir's Logger
config :logger,
  backends: [
    :console,
    # error logs are also send to sentry
    Sentry.LoggerBackend
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :scrivener_html,
  routes_helper: TransportWeb.Router.Helpers

# Allow to have Markdown templates
config :phoenix, :template_engines,
  md: PhoenixMarkdown.Engine,
  leex: Phoenix.LiveView.Engine

config :phoenix_markdown, :server_tags, :all

# build sentry env based on Mix env, unless overriden (useful for staging)
sentry_env_as_atom =
  if v = System.get_env("SENTRY_ENV") do
    v |> String.to_atom()
  else
    config_env()
  end

# check out https://sentry.io/settings/transport-data-gouv-fr/projects/transport-site/install/elixir/
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: sentry_env_as_atom,
  included_environments: [:prod, :staging],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  filter: Transport.Shared.SentryExceptionFilter,
  # the key must be there for overriding during tests,
  # so we set it to the default based on source code for now
  send_result: :none

config :transport,
  cache_impl: Transport.Cache.Cachex,
  ex_aws_impl: ExAws,
  httpoison_impl: HTTPoison,
  history_impl: Transport.History.Fetcher.Database,
  rambo_impl: Transport.Rambo,
  gbfs_metadata_impl: Transport.Shared.GBFSMetadata,
  availability_checker_impl: Transport.AvailabilityChecker,
  jsonschema_validator_impl: Shared.Validation.JSONSchemaValidator,
  tableschema_validator_impl: Shared.Validation.TableSchemaValidator,
  schemas_impl: Transport.Shared.Schemas,
  hasher_impl: Hasher,
  validator_selection: Transport.ValidatorsSelection.Impl,
  data_visualization: Transport.DataVisualization.Impl

# Datagouv IDs for national databases created automatically.
# These are IDs used in staging, demo.data.gouv.fr
config :transport,
  consolidation: %{
    zfe: %{
      dataset_id: "624ff4b1bbb449a550264040",
      resource_ids: %{
        "voies" => "98c6bcdb-1205-4481-8859-f885290763f2",
        "aires" => "3ddd29ee-00dd-40af-bc98-3367adbd0289"
      }
    }
  }

config :transport,
  datagouv_static_hosts: ["static.data.gouv.fr", "demo-static.data.gouv.fr"],
  bison_fute_host: "tipi.bison-fute.gouv.fr"

config :datagouvfr,
  community_resources_impl: Datagouvfr.Client.CommunityResources.API,
  authentication_impl: Datagouvfr.Authentication,
  user_impl: Datagouvfr.Client.User

config :ex_json_schema,
       :remote_schema_resolver,
       fn url -> HTTPoison.get!(url).body |> Jason.decode!() end

config :ex_aws,
  access_key_id: System.get_env("CELLAR_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("CELLAR_SECRET_ACCESS_KEY"),
  # The expected S3 owner of buckets/objects.
  # For CleverCloud and the Cellar service, it looks like `orga-$UUID`
  cellar_organisation_id: System.get_env("CELLAR_ORGANISATION_ID"),
  # ~s is a string parameter, it will be replaced by the bucket's name
  cellar_url: "https://~s.cellar-c2.services.clever-cloud.com",
  s3: [
    scheme: "https://",
    host: "cellar-c2.services.clever-cloud.com"
  ],
  json_codec: Jason

config :transport,
  domain_name: System.get_env("DOMAIN_NAME", "transport.data.gouv.fr"),
  max_import_concurrent_jobs: (System.get_env("MAX_IMPORT_CONCURRENT_JOBS") || "1") |> String.to_integer(),
  nb_days_to_keep_validations: 60,
  join_our_slack_link: "https://join.slack.com/t/transportdatagouvfr/shared_invite/zt-2n1n92ye-sdGQ9SeMh5BkgseaIzV8kA",
  contact_email: "contact@transport.beta.gouv.fr",
  security_email: "contact@transport.beta.gouv.fr",
  transport_tools_folder: Path.absname("transport-tools/"),
  notifications_impl: Transport.Notifications.GitHub,
  notifications_github_config_url: "https://raw.githubusercontent.com/etalab/transport-notifications/master/config.yml",
  notifications_github_auth_token: System.get_env("TRANSPORT_NOTIFICATIONS_CONFIG_GITHUB_TOKEN"),
  notifications_api_token: System.get_env("TRANSPORT_NOTIFICATIONS_API_TOKEN")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "datagouvfr.exs"
import_config "database.exs"
import_config "gtfs_validator.exs"
import_config "gbfs_validator.exs"
import_config "mailjet.exs"
import_config "mailchimp.exs"
import_config "#{config_env()}.exs"
