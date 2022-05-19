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
  webserver: webserver

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

config :transport,
  app_env: app_env

# Override configuration specific to staging
if app_env == :staging do
  config :transport,
    s3_buckets: %{
      history: "resource-history-staging",
      on_demand_validation: "on-demand-validation-staging"
    }
end

base_oban_conf = [repo: DB.Repo]

# Oban jobs that should run in every deployed environment (staging, prod)
# but not during dev or test
# Be careful : there is "app_env :prod" in contrast  to :staging (ie production website vs prochainement)
# and "config_env :prod" in contrast to :dev et :test
oban_crontab_all_envs =
  case config_env() do
    :prod ->
      [
        {"0 */6 * * *", Transport.Jobs.ResourceHistoryDispatcherJob},
        {"30 */6 * * *", Transport.Jobs.GtfsToGeojsonConverterJob},
        # every 6 hours but not at the same time as other jobs
        {"0 3,9,15,21 * * *", Transport.Jobs.GtfsToNetexConverterJob},
        {"20 8 * * *", Transport.Jobs.CleanOrphanConversionsJob},
        {"0 * * * *", Transport.Jobs.ResourcesUnavailableDispatcherJob},
        {"*/10 * * * *", Transport.Jobs.ResourcesUnavailableDispatcherJob, args: %{only_unavailable: true}},
        {"20 */2 * * *", Transport.Jobs.GTFSRTEntitiesDispatcherJob},
        {"30 */6 * * *", Transport.Jobs.BNLCToGeoData},
        {"15 10 * * *", Transport.Jobs.DatabaseBackupReplicationJob}
      ]

    :dev ->
      []

    :test ->
      []
  end

# Oban jobs that *should not* be run in staging (ie on prochainement) by the crontab
non_staging_crontab =
  if app_env == :staging do
    []
  else
    # Oban jobs that should be run in all envs, *except* staging
    # avoid overloading external validators
    [{"0 2,8,14,20 * * *", Transport.Jobs.ResourceHistoryValidationJob}]
  end

extra_oban_conf =
  if not worker || iex_started? || config_env() == :test do
    [queues: false, plugins: false]
  else
    [
      queues: [default: 2, heavy: 1, on_demand_validation: 1, resource_history_validation: 1],
      plugins: [
        {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
        {Oban.Plugins.Cron, crontab: List.flatten(oban_crontab_all_envs, non_staging_crontab)}
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

email_host_name =
  case config_env() do
    :dev ->
      "localhost"

    :test ->
      # used to make sure we are replacing the app host name by the email host name
      # when it is different, in some email testing
      "email.localhost"

    :prod ->
      # NOTE: it would be best to configure this via EMAIL_HOST_NAME var instead,
      # but that will do for today.
      case app_env do
        :staging -> "prochainement.transport.data.gouv.fr"
        :production -> "transport.data.gouv.fr"
      end
  end

config :transport, :email_host_name, email_host_name

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
    # See https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config
    # [Ecto.Repo] :pool_timeout is no longer supported in favor of a new queue system described in DBConnection.start_link/2
    # under "Queue config". For most users, configuring :timeout is enough, as it now includes both queue and query time
    timeout: 15_000

  if app_env == :production do
    # Datagouv IDs for national databases created automatically and
    # published by us on data.gouv.fr
    config :transport,
      consolidation: %{
        zfe: %{
          dataset_id: "625438b890bf88454b283a55",
          resource_ids: %{
            "voies" => "3a5d0c66-aef9-4d68-841f-4fe81c9de980",
            "aires" => "673a16bf-49ec-4645-9da2-cf975d0aa0ea"
          }
        }
      }
  end
end
