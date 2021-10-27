import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if config_env() == :prod do
  worker = System.get_env("WORKER") || raise "expected the WORKER environment variable to be set"
  webserver = System.get_env("WEBSERVER") || raise "expected the WEBSERVER environment variable to be set"

  config :transport,
    worker: worker,
    webserver: webserver

  # Scheduled jobs are run in production on the worker only
  # TODO handle case with multiple workers
  scheduled_jobs = if worker == "1", do: Transport.Scheduler.scheduled_jobs(), else: []

  config :transport, Transport.Scheduler,
    jobs: scheduled_jobs
end

if config_env() == :dev do
  # By default in dev, the application will be both a worker and a webserver
  worker = System.get_env("WORKER") || "1"
  webserver = System.get_env("WEBSERVER") || "1"

  config :transport,
    worker: worker,
    webserver: webserver,
end

if config_env() != :test do
  # TODO queue size could be defined with ENV variable
  config :transport, Oban, queues: [default: 1]
end
