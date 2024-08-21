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

# see health-check ; manually cutting unused ports for now
config :os_mon,
  start_cpu_sup: false,
  start_disksup: false,
  start_memsup: true

config :unlock,
  config_fetcher: Unlock.Config.GitHub,
  http_client: Unlock.HTTP.FinchImpl,
  github_config_url: "https://raw.githubusercontent.com/etalab/transport-proxy-config/master/proxy-config.yml",
  github_auth_token: System.get_env("TRANSPORT_PROXY_CONFIG_GITHUB_TOKEN"),
  siri_public_requestor_ref: "transport-data-gouv-fr"

# NOTE: the config is unused by the app (because the endpoint is not used, the
# unlock router is directly wired into the main transport endpoint). The config key
# is nonetheless present to avoid a warning at runtime / test time.
config :unlock, Unlock.Endpoint, []

if System.get_env("CELLAR_NAMESPACE") do
  # We believe CELLAR_NAMESPACE was a previous attempt at siloting S3 envs.
  # We will instead rely on separate buckets in the short-term future.
  raise "CELLAR_NAMESPACE variable is deprecated and must be removed."
end

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
    # Error logs are also sent to Sentry
    Sentry.LoggerBackend
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  # :remote_ip is set by the dependency `remote_ip`
  # `:(method|path|user_agent)` are set by TransportWeb.Plugs.RateLimiter only
  # when LOG_USER_AGENT=true
  metadata: [:request_id, :remote_ip, :method, :path, :user_agent]

config :scrivener_html,
  routes_helper: TransportWeb.Router.Helpers

# Allow to have Markdown templates
config :phoenix, :template_engines,
  md: PhoenixMarkdown.Engine,
  leex: Phoenix.LiveView.Engine

config :phoenix_markdown, :server_tags, :all

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
  data_visualization: Transport.DataVisualization.Impl,
  workflow_notifier: Transport.Jobs.Workflow.ObanNotifier,
  enroute_validator_client: Transport.EnRouteChouetteValidClient

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
    },
    # These are production IDs
    bnlc: %{
      dataset_id: "5d6eaffc8b4c417cdc452ac3",
      resource_id: "4fd78dee-e122-4c0d-8bf6-ff55d79f3af1"
    },
    irve: %{
      resource_id: "eb76d20a-8501-400e-b336-d85724de5435"
    }
  }

config :transport,
  datagouv_static_hosts: ["static.data.gouv.fr", "demo-static.data.gouv.fr"],
  bison_fute_host: "tipi.bison-fute.gouv.fr"

config :datagouvfr,
  community_resources_impl: Datagouvfr.Client.CommunityResources.API,
  authentication_impl: Datagouvfr.Authentication,
  user_impl: Datagouvfr.Client.User,
  datagouvfr_reuses: Datagouvfr.Client.Reuses,
  datagouvfr_discussions: Datagouvfr.Client.Discussions,
  organization_impl: Datagouvfr.Client.Organization,
  # The two following implementations are also used in tests, except if specifically overriden to use a mock
  # Because legacy tests mock at a lower level (HTTPoison), we need to keep the same behavior for now
  datasets_impl: Datagouvfr.Client.Datasets.External,
  resources_impl: Datagouvfr.Client.Resources.External

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

config :ex_aws, :database_backup_source,
  access_key_id: System.get_env("DATABASE_BACKUP_SOURCE_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("DATABASE_BACKUP_SOURCE_SECRET_ACCESS_KEY"),
  bucket_name: System.get_env("DATABASE_BACKUP_SOURCE_BUCKET_NAME"),
  host: System.get_env("DATABASE_BACKUP_SOURCE_HOST"),
  region: System.get_env("DATABASE_BACKUP_SOURCE_REGION")

config :ex_aws, :database_backup_destination,
  access_key_id: System.get_env("DATABASE_BACKUP_DESTINATION_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("DATABASE_BACKUP_DESTINATION_SECRET_ACCESS_KEY"),
  bucket_name: System.get_env("DATABASE_BACKUP_DESTINATION_BUCKET_NAME"),
  host: System.get_env("DATABASE_BACKUP_DESTINATION_HOST"),
  region: System.get_env("DATABASE_BACKUP_DESTINATION_REGION")

# https://hexdocs.pm/gettext/Gettext.html#module-default-locale
config :gettext, :default_locale, "fr"

config :transport,
  domain_name: System.get_env("DOMAIN_NAME", "transport.data.gouv.fr"),
  export_secret_key: System.get_env("EXPORT_SECRET_KEY"),
  enroute_token: System.get_env("ENROUTE_TOKEN"),
  enroute_validation_token: System.get_env("ENROUTE_VALIDATION_TOKEN"),
  max_import_concurrent_jobs: (System.get_env("MAX_IMPORT_CONCURRENT_JOBS") || "1") |> String.to_integer(),
  nb_days_to_keep_validations: 60,
  join_our_slack_link: "https://join.slack.com/t/transportdatagouvfr/shared_invite/zt-2n1n92ye-sdGQ9SeMh5BkgseaIzV8kA",
  contact_email: "contact@transport.data.gouv.fr",
  bizdev_email: "deploiement@transport.data.gouv.fr",
  tech_email: "tech@transport.data.gouv.fr",
  security_email: "contact@transport.data.gouv.fr",
  transport_tools_folder: Path.absname("transport-tools/")

# Disable sending events to Sentry by default.
# Events are sent in production and staging, configured in `prod.exs`
config :sentry, dsn: nil

# For now, never send session data (containing sensitive data in our case) nor params,
# even if this means less useful information.
# See https://github.com/etalab/transport_deploy/issues/64
config :appsignal, :config,
  # https://docs.appsignal.com/ruby/configuration/options.html#option-send_session_data
  send_session_data: false,
  # https://docs.appsignal.com/ruby/configuration/options.html#option-send_params
  send_params: false,
  # we use a plug which sets the namespace as ignore programmatically
  # and here declare that the corresponding requests should be ignored
  ignore_namespaces: ["ignore"],
  # would generate too much noise for now, shutting it down
  instrument_oban: false,
  report_oban_errors: false,
  # but this is not always enough:
  ignore_actions: [
    # without this action, requests will be counted twice
    # I presume this is triggered by the way we route requests
    # https://github.com/etalab/transport-site/blob/master/apps/transport/lib/transport_web/plugs/router.ex
    "GET /*_path",
    # Here this is a duplicate precaution to ensure we exclude proxy
    # traffic which generates a lot of AppSignal events
    "Unlock.Controller#fetch"
  ]

# `phoenix_ddos` is called in our own Plug `TransportWeb.Plugs.RateLimiter`
config :phoenix_ddos,
  safelist_ips: "PHOENIX_DDOS_SAFELIST_IPS" |> System.get_env("") |> String.split("|") |> Enum.reject(&(&1 == "")),
  blocklist_ips: "PHOENIX_DDOS_BLOCKLIST_IPS" |> System.get_env("") |> String.split("|") |> Enum.reject(&(&1 == "")),
  protections: [
    # ip rate limit
    {PhoenixDDoS.IpRateLimit,
     allowed: "PHOENIX_DDOS_MAX_2MIN_REQUESTS" |> System.get_env("500") |> Integer.parse() |> elem(0),
     period: {2, :minutes}},
    {PhoenixDDoS.IpRateLimit,
     allowed: "PHOENIX_DDOS_MAX_1HOUR_REQUESTS" |> System.get_env("10000") |> Integer.parse() |> elem(0),
     period: {1, :hour}}
    # ip rate limit on specific request_path
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "datagouvfr.exs"
import_config "database.exs"
import_config "gtfs_validator.exs"
import_config "gbfs_validator.exs"
import_config "mail.exs"
import_config "mailchimp.exs"
import_config "#{config_env()}.exs"
