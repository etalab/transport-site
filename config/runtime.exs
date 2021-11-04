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

# expose the result so that the application can configure itself from there
config :transport,
  worker: worker,
  webserver: webserver

# Scheduled jobs (via Quantum at this point) are run in production and only on the first worker node
# https://www.clever-cloud.com/doc/reference/reference-environment-variables/#set-by-the-deployment-process
if config_env() == :prod && worker && System.fetch_env!("INSTANCE_NUMBER") == "0" do
  config :transport, Transport.Scheduler, jobs: Transport.Scheduler.scheduled_jobs()
end

# Inside IEx, we do not want jobs to start processing, nor plugins working.
# The jobs can be heavy and for instance in production, one person could
# unknowningly create duplicate RAM heavy jobs. With this trick, we can still
# enqueue jobs from IEx, but only the real worker will process them
# See https://github.com/sorentwo/oban/issues/520#issuecomment-883416363

iex_started? = Code.ensure_loaded?(IEx) && IEx.started?()
base_oban_conf = [repo: DB.Repo]

extra_oban_conf =
  if worker != "1" || iex_started? || config_env() == :test do
    [queues: false, plugins: false]
  else
    [
      queues: [default: 25, heavy: 1],
      plugins: [Oban.Plugins.Pruner]
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
    watchers: if(webserver == "1", do: [npm: ["run", "--prefix", "apps/transport/client", "watch"]], else: [])
end
