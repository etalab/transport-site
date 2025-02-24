import Config

require Logger

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

{worker, webserver} =
  case config_env() do
    :prod ->
      {
        System.get_env("WORKER") || raise("expected the WORKER environment variable to be set"),
        System.get_env("WEBSERVER") || raise("expected the WEBSERVER variable to be set")
      }

    :dev ->
      # By default in dev, the application will be both a worker and a webserver
      {
        System.get_env("WORKER", "1"),
        System.get_env("WEBSERVER", "1")
      }

    :test ->
      {
        "0",
        "0"
      }
  end

worker = worker == "1"
webserver = webserver == "1"

# expose the result so that the application can configure itself from there
config :transport,
  worker: worker,
  webserver: webserver,
  # kill switches: set specific variable environments to disable features
  disable_national_gtfs_map: System.get_env("DISABLE_NATIONAL_GTFS_MAP") in ["1", "true"],
  disable_netex_validator: System.get_env("DISABLE_NETEX_VALIDATOR") in ["1", "true"]

config :unlock,
  enforce_ttl: webserver

# Inside IEx, we do not want jobs to start processing, nor plugins working.
# The jobs can be heavy and for instance in production, one person could
# unknowningly create duplicate RAM heavy jobs. With this trick, we can still
# enqueue jobs from IEx, but only the real worker will process them
# See https://github.com/sorentwo/oban/issues/520#issuecomment-883416363
iex_started? = Code.ensure_loaded?(IEx) && IEx.started?()

# Scheduled jobs (via Quantum at this point) are run in production and only on the first worker node
# https://www.clever-cloud.com/doc/reference/reference-environment-variables/#set-by-the-deployment-process
# They should not run in an iex session either.
if config_env() == :prod && !iex_started? && worker && System.fetch_env!("INSTANCE_NUMBER") == "0" do
  config :transport, Transport.Scheduler, jobs: Transport.Scheduler.scheduled_jobs()
end

# Make sure that APP_ENV is set in production to distinguish
# production and staging (both running with MIX_ENV=prod)
# See https://github.com/etalab/transport-site/issues/1945
app_env = System.get_env("APP_ENV", "") |> String.to_atom()
app_env_is_valid = Enum.member?([:production, :staging], app_env)

if config_env() == :prod and not app_env_is_valid do
  raise("APP_ENV must be set to production or staging while in production")
end

# on staging, allow override of configuration so that we can target other branches
if app_env == :staging do
  if url = System.get_env("TRANSPORT_PROXY_CONFIG_GITHUB_URL") do
    config :unlock, github_config_url: url
  end
end

domain_name =
  case config_env() do
    :prod -> System.fetch_env!("DOMAIN_NAME")
    :test -> "www.example.com"
    :dev -> "localhost"
  end

config :transport, domain_name: domain_name

config :transport,
  app_env: app_env

# Override configuration specific to staging
if app_env == :staging do
  config :transport,
    s3_buckets: %{
      history: "resource-history-staging",
      on_demand_validation: "on-demand-validation-staging",
      gtfs_diff: "gtfs-diff-staging",
      logos: "logos-staging",
      aggregates: "aggregates-staging"
    }
end

base_oban_conf = [repo: DB.Repo, insert_trigger: false]

# Oban jobs that should run in every deployed environment (staging, prod)
# but not during dev or test.
#
# - There is "app_env :prod" in contrast to :staging (ie production website vs prochainement)
#   and "config_env :prod" in contrast to :dev et :test
# - ⚠️ There is another legacy crontab in `Transport.Scheduler`, see `scheduler.ex`
# See https://hexdocs.pm/oban/Oban.html#module-cron-expressions
oban_prod_crontab = [
  {"0 */6 * * *", Transport.Jobs.ResourceHistoryAndValidationDispatcherJob},
  {"30 */6 * * *", Transport.Jobs.GTFSToGeoJSONConverterJob},
  {"0 4 * * *", Transport.Jobs.GTFSImportStopsJob},
  # every 6 hours but not at the same time as other jobs
  {"0 3,9,15,21 * * *", Transport.Jobs.GTFSToNeTExConverterJob},
  {"20 8 * * *", Transport.Jobs.CleanOrphanConversionsJob},
  {"0 * * * *", Transport.Jobs.ResourcesUnavailableDispatcherJob},
  {"*/10 * * * *", Transport.Jobs.ResourcesUnavailableDispatcherJob, args: %{only_unavailable: true}},
  {"20 */2 * * *", Transport.Jobs.GTFSRTMetadataDispatcherJob},
  {"30 */6 * * *", Transport.Jobs.BNLCToGeoData},
  {"30 */6 * * *", Transport.Jobs.ParkingsRelaisToGeoData},
  {"30 */6 * * *", Transport.Jobs.LowEmissionZonesToGeoData},
  {"30 */6 * * *", Transport.Jobs.IRVEToGeoData},
  {"30 6 * * *", Transport.Jobs.GBFSStationsToGeoData},
  {"15 10 * * *", Transport.Jobs.DatabaseBackupReplicationJob},
  {"0 7 * * *", Transport.Jobs.GTFSRTMultiValidationDispatcherJob},
  {"30 7 * * *", Transport.Jobs.GBFSMultiValidationDispatcherJob},
  {"45 */3 * * *", Transport.Jobs.ResourceHistoryJSONSchemaValidationJob},
  # Validata JSON is not properly maintained/monitored.
  # Disable it for now.
  # https://github.com/etalab/transport-site/issues/3492
  # {"0 20 * * *", Transport.Jobs.ResourceHistoryValidataJSONJob},
  {"15 */3 * * *", Transport.Jobs.ResourceHistoryTableSchemaValidationJob},
  {"0 6 * * 1-5", Transport.Jobs.NewDatagouvDatasetsJob, args: %{check_rules: true}},
  {"5 6 * * 1-5", Transport.Jobs.NewDatagouvDatasetsJob},
  {"0 6 * * *", Transport.Jobs.NewDatasetNotificationsJob},
  {"30 6 * * *", Transport.Jobs.ExpirationAdminProducerNotificationJob},
  {"45 6 * * *", Transport.Jobs.ExpirationNotificationJob},
  {"0 8 * * 1-5", Transport.Jobs.NewCommentsNotificationJob},
  {"0 21 * * *", Transport.Jobs.DatasetHistoryDispatcherJob},
  # Should be executed after all `DatasetHistoryJob` have been executed
  {"50 21 * * *", Transport.Jobs.ResourcesChangedNotificationJob},
  {"0 22 * * *", Transport.Jobs.ArchiveMetricsJob},
  {"15,45 * * * *", Transport.Jobs.MultiValidationWithErrorNotificationJob},
  {"20,50 * * * *", Transport.Jobs.ResourceUnavailableNotificationJob},
  {"30 6 * * 1", Transport.Jobs.DatasetsSwitchingClimateResilienceBillJob},
  {"30 6 * * 1-5", Transport.Jobs.DatasetsClimateResilienceBillNotLOLicenceJob},
  {"10 6 * * 1", Transport.Jobs.DatasetsWithoutGTFSRTRelatedResourcesNotificationJob},
  {"10 6 * * 1", Transport.Jobs.GBFSOperatorsNotificationJob},
  {"45 2 * * *", Transport.Jobs.RemoveHistoryJob, args: %{schema_name: "etalab/schema-irve-dynamique", days_limit: 7}},
  {"0 16 * * *", Transport.Jobs.DatasetQualityScoreDispatcher},
  {"40 3 * * *", Transport.Jobs.UpdateContactsJob},
  {"10 5 * * *", Transport.Jobs.NotificationSubscriptionProducerJob},
  # "At 08:15 on Monday in March, June, and November.""
  # The job will make sure that it's executed only on the first Monday of these months
  {"15 8 * 3,6,11 1", Transport.Jobs.PeriodicReminderProducersNotificationJob},
  {"15 5 * * *", Transport.Jobs.ImportDatasetFollowersJob},
  {"5 5 * * *", Transport.Jobs.ImportDatasetFollowerReuserImprovedDataJob},
  {"20 5 * * *", Transport.Jobs.ImportDatasetContactPointsJob},
  # Should be ideally executed after `GBFSMultiValidationDispatcherJob` to use fresh metadata
  {"30 8 * * *", Transport.Jobs.ImportGBFSFeedContactEmailJob},
  {"30 5 * * *", Transport.Jobs.ImportDatasetMonthlyMetricsJob},
  {"45 5 * * *", Transport.Jobs.ImportResourceMonthlyMetricsJob},
  {"0 8 * * *", Transport.Jobs.WarnUserInactivityJob},
  {"*/5 * * * *", Transport.Jobs.UpdateCounterCacheJob},
  {"0 4 * * *", Transport.Jobs.StopsRegistrySnapshotJob}
]

# Make sure that all modules exist
oban_prod_crontab |> Enum.map(&Code.ensure_compiled!(elem(&1, 1)))

oban_crontab_all_envs =
  case config_env() do
    :prod -> oban_prod_crontab
    :dev -> []
    :test -> []
  end

# Oban Jobs that only run on the production server.
production_server_crontab =
  if app_env == :production and config_env() == :prod do
    # GTFS validations can be heavy for the validator, we run them only on the production server
    [{"0 2,8,14,20 * * *", Transport.Jobs.GTFSValidationJob}]
  else
    []
  end

extra_oban_conf =
  if not worker || iex_started? || config_env() == :test do
    [testing: :manual]
  else
    [
      queues: [
        default: 2,
        enroute_conversions: 10,
        heavy: 1,
        on_demand_validation: 1,
        resource_validation: 1,
        workflow: 2
      ],
      plugins: [
        {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
        {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)},
        {Oban.Plugins.Cron, crontab: List.flatten(oban_crontab_all_envs, production_server_crontab)}
      ]
    ]
  end

config :transport, Oban, Keyword.merge(base_oban_conf, extra_oban_conf)

# here we only override specific keys. As documented in https://hexdocs.pm/elixir/master/Config.html#config/2,
# for keywords there is a recursive deep-merge, which should work nicely here.
if config_env() == :dev do
  config :transport, TransportWeb.Endpoint,
    # optionally allowing to override the port is useful to play with 2 nodes locally, without conflict
    http: [port: System.get_env("PORT", "5000")],
    #  We also make sure to start the assets watcher only if the webserver is up, to avoid cluttering the logs.
    watchers: if(webserver, do: [npm: ["run", "--prefix", "apps/transport/client", "watch"]], else: [])
end

if config_env() == :prod do
  pool_size =
    case app_env do
      :production -> 15
      :staging -> 6
    end

  config :transport, DB.Repo,
    url:
      System.get_env("POSTGRESQL_ADDON_DIRECT_URI") || System.get_env("POSTGRESQL_ADDON_URI") ||
        "" |> String.replace_prefix("postgresql", "ecto"),
    # NOTE: we must be careful with this ; front-end + worker are consuming
    pool_size: pool_size,
    # Broken TCP connections can stop Oban from polling jobs
    # https://github.com/sorentwo/oban/issues/493#issuecomment-1187001822
    # https://github.com/sorentwo/oban/issues/769 is not released yet,
    # the alternative is to use this configuration or use [the Repeater
    # plugin](https://hexdocs.pm/oban/Oban.Plugins.Repeater.html).
    # https://github.com/sorentwo/oban/issues/821#issuecomment-1369218531
    parameters: [
      tcp_keepalives_idle: "60",
      tcp_keepalives_interval: "5",
      tcp_keepalives_count: "3"
    ],
    socket_options: [keepalive: true],
    # See https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config
    # [Ecto.Repo] :pool_timeout is no longer supported in favor of a new queue system described in DBConnection.start_link/2
    # under "Queue config". For most users, configuring :timeout is enough, as it now includes both queue and query time
    timeout: 15_000

  config :transport, TransportWeb.Endpoint,
    http: [port: System.get_env("PORT"), compress: true],
    url: [scheme: "https", host: System.get_env("DOMAIN_NAME"), port: 443],
    cache_static_manifest: "priv/static/cache_manifest.json",
    secret_key_base: System.get_env("SECRET_KEY_BASE"),
    force_ssl: [rewrite_on: [:x_forwarded_proto]],
    live_view: [
      signing_salt: System.get_env("SECRET_KEY_BASE")
    ]

  if app_env == :production do
    # data.gouv.fr IDs for national databases created automatically and
    # published by us on data.gouv.fr.
    # Overrides values set in `config.exs`
    config :transport,
      consolidation:
        Map.merge(Application.fetch_env!(:transport, :consolidation), %{
          zfe: %{
            dataset_id: "625438b890bf88454b283a55",
            resource_ids: %{
              "voies" => "3a5d0c66-aef9-4d68-841f-4fe81c9de980",
              "aires" => "673a16bf-49ec-4645-9da2-cf975d0aa0ea"
            }
          }
        })

    config :transport, Transport.Mailer,
      adapter: Swoosh.Adapters.Mailjet,
      api_key: System.fetch_env!("MJ_APIKEY_PUBLIC"),
      secret: System.fetch_env!("MJ_APIKEY_PRIVATE")
  end
end

# On Clever Cloud, each container gets assigned a UUID, which gets propagated to AppSignal.
# It is easier to assign the container a "role" so that we can more easily charts relevant metrics.
host_role =
  []
  |> Kernel.++(if webserver, do: ["site"], else: [])
  |> Kernel.++(if worker, do: ["worker"], else: [])
  |> Enum.join("-")

# NOTE: for dev work, use dev.secret.exs instead
if config_env() == :prod do
  # staging vs production
  app_signal_env = app_env

  # inspired from the installer and
  # https://docs.appsignal.com/elixir/configuration.html

  # revision tracking is helpful to track optimisations & regressions
  {revision, exitcode} = System.cmd("git", ["log", "--pretty=format:%h", "-n 1"])
  revision = if exitcode == 0, do: revision, else: nil

  config :appsignal, :config,
    # https://docs.appsignal.com/elixir/integrations/ecto.html
    otp_app: :transport,
    # NOTE: not directly using APPSIGNAL_* variables to let us decide programmatically,
    # because APPSIGNAL_* variables take precedence
    name: System.get_env("CUSTOM_APPSIGNAL_APP_NAME", "transport.data.gouv.fr"),
    push_api_key: System.get_env("CUSTOM_APPSIGNAL_PUSH_API_KEY"),
    env: app_signal_env,
    host_role: host_role,
    revision: revision,
    active: true
end
