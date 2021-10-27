import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

worker = System.get_env("WORKER") || raise "expected the WORKER environment variable to be set"

config :transport,
  worker: worker

# scheduled jobs are run in production on the worker only
# TODO handle case with multiple workers
scheduled_jobs = case {config_env(), worker} do
  {:prod, "1"} -> Transport.Scheduler.scheduled_jobs()
  _ -> []
end

config :transport, Transport.Scheduler,
  jobs: scheduled_jobs
