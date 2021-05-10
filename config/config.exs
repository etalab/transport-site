# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

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
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: GBFS.ErrorView, accepts: ~w(json)],
  pubsub_server: GBFS.PubSub, # TODO: verify if this is truly needed? unsure.
  server: false

# Configures the endpoint
config :transport, TransportWeb.Endpoint,
  url: [host: "127.0.0.1"],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [
    view: TransportWeb.ErrorView,
    layout: {TransportWeb.LayoutView, "app.html"},
    accepts: ~w(html json)
  ],
  pubsub_server: TransportWeb.PubSub,
  live_view: [
    signing_salt: System.get_env("SECRET_KEY_BASE")
  ]

config :phoenix, :json_library, Jason

#
# A tweaked format encoder to optionally bypass JSON
# encoding when the caller knows it is already encoded.
#
# See https://hexdocs.pm/phoenix/1.5.8/Phoenix.Template.html#module-format-encoders
#
config :phoenix, :format_encoders,
  json: TransportWeb.ConditionalJSONEncoder

# Configures Elixir's Logger
config :logger,
  backends: [
    :console,
    Sentry.LoggerBackend # error logs are also send to sentry
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :scrivener_html,
  routes_helper: TransportWeb.Router.Helpers

# Allow to have Markdown templates
config :phoenix, :template_engines,
  [
    md: PhoenixMarkdown.Engine,
    leex: Phoenix.LiveView.Engine
  ]

config :phoenix_markdown, :server_tags, :all

# build sentry env based on Mix env, unless overriden (useful for staging)
sentry_env_as_atom = if v = System.get_env("SENTRY_ENV") do
  v |> String.to_atom()
else
  Mix.env()
end

# check out https://sentry.io/settings/transport-data-gouv-fr/projects/transport-site/install/elixir/
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: sentry_env_as_atom,
  included_environments: [:prod, :staging],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!,
  filter: Transport.Shared.SentryExceptionFilter,
  # the key must be there for overriding during tests,
  # so we set it to the default based on source code for now
  send_result: :none

config :transport,
  cache_impl: Transport.Cache.Cachex,
  ex_aws_impl: ExAws

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "datagouvfr.exs"
import_config "database.exs"
import_config "gtfs_validator.exs"
import_config "mailjet.exs"
import_config "mailchimp.exs"
import_config "#{Mix.env}.exs"

config :ex_aws,
  access_key_id: System.get_env("CELLAR_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("CELLAR_SECRET_ACCESS_KEY"),
  s3: [
    scheme: "https://",
    host: "cellar-c2.services.clever-cloud.com",
  ],
  json_codec: Jason

config :transport,
  max_import_concurrent_jobs: (System.get_env("MAX_IMPORT_CONCURRENT_JOBS") || "1") |> String.to_integer(),
  nb_days_to_keep_validations: 60,
  join_our_slack_link: "https://join.slack.com/t/transportdatagouvfr/shared_invite/zt-2n1n92ye-sdGQ9SeMh5BkgseaIzV8kA"
