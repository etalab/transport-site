# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

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

# Configures format encoders
config :phoenix, :format_encoders,
  html: Phoenix.Template.HTML,
  json: Jason

# Configures Elixir's Logger
config :logger,
  handle_otp_reports: true,
  handle_sasl_reports: true,
  translators: [
    {Support.Logger.Translator, :translate},
    {Logger.Translator, :translate}
  ],
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

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: Mix.env,
  enable_source_code_context: true,
  root_source_code_path: File.cwd!,
  tags: %{
    env: "production"
  },
  included_environments: [:prod]


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
