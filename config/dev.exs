use Mix.Config

config :transport, TransportWeb.Endpoint,
  http: [port: 5000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    npm: ["run", "--prefix", "apps/transport/client", "watch"]
  ]

config :transport, TransportWeb.Endpoint,
  live_reload: [
    url: "ws://127.0.0.1:5000",
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/transport_web/views/.*(ex)$},
      ~r{lib/transport_web/templates/.*(eex|md)$},
      ~r{lib/transport_web/live/.*(ex)$}
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# By default, in development we'll use a mock history fetcher, which
# means no history is displayed.
#
# If you need to target an actual CleverCloud bucket temporarily,
# just comment-out what is below and configure via envrc for now.
# In a later version we may use dev.secret.exs file (out of git)
# as often done.
config :transport,
  history_impl: Transport.History.Fetcher.Mock
