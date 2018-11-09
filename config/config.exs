# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :transportsite,
  ecto_repos: [Transportsite.Repo]

# Configures the endpoint
config :transportsite, TransportsiteWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "F/H0sYthPuJEMpZ2fbmSJJD10LIrzYiHE8SVIHubG6eWu/IKxc1j0TwzjrzShryI",
  render_errors: [view: TransportsiteWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Transportsite.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
