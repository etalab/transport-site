# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :transport, TransportWeb.Endpoint,
  url: [host: "127.0.0.1"],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [
    view: TransportWeb.ErrorView,
    layout: {TransportWeb.LayoutView, "app.html"},
    accepts: ~w(html json jsonapi)
  ],
  pubsub: [name: Transport.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures format encoders
config :phoenix, :format_encoders,
  html: Phoenix.Template.HTML,
  json: Poison,
  jsonapi: Poison

# Configures MIME types
config :mime, :types, %{
  "application/vnd.api+json" => ["jsonapi"]
}

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "amqp.exs"
import_config "datagouvfr.exs"
import_config "datatools.exs"
import_config "mailgun.exs"
import_config "mongodb.exs"
import_config "#{Mix.env}.exs"
