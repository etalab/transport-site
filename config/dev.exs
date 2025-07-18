import Config

# For local work, it is usually more convenient to copy-paste
config :unlock,
  config_fetcher: Unlock.Config.Disk,
  disk_config_file: Path.join(__DIR__, "proxy-config.yml")

config :transport, TransportWeb.Endpoint,
  # http: is configured via config/runtime.exs (PORT)
  debug_errors: true,
  # If you want to test persistence of forms across deploys in development,
  # make sure to set code_reloader to false.
  # see https://hexdocs.pm/phoenix_live_view/form-bindings.html#recovery-following-crashes-or-disconnects
  # for the detailed explanation.
  code_reloader: true,
  check_origin: false,
  # NOTE: this is required to ensure code reloading will work.
  # A page reload is required to trigger this. More apps could
  # be added when needed here, we just added what we needed.
  reloadable_apps: [:shared, :transport, :unlock, :datagouvfr]

# Uncomment this to avoid having to restart the app for each change in description
# See https://github.com/open-api-spex/open_api_spex#serve-the-spec
# config :open_api_spex, :cache_adapter, OpenApiSpex.Plug.NoneCache

# watchers are also configured via config/runtime.exs

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

# Swap out some implementations in developement to ease setup and
# integration with third party services.
#
# Edit the following lines if you want to use another implementation.
# You can use dev.secret.exs (out of git) if you need to set secrets
# as often done.

# Provide a default experience that will mostly work without manual config,
# as long as the developer does not use advanced features (backoffice login, gbfs etc)
# One can use dev.secret.exs to override this.
secret_key_base = "lrS928IORjEwtIIdxjRZ30I8PUR4rbXorGCfmA4nbX2Jkgjl7U9rpcz6QjjH1AOc"

config :transport, TransportWeb.Endpoint,
  secret_key_base: secret_key_base,
  live_view: [
    # NOTE: unsure if this is actually great to reuse the same value
    signing_salt: secret_key_base
  ],
  export_secret_key: System.get_env("EXPORT_SECRET_KEY", "TwqrkD06AWp1uKGcBTck")

datagouvfr_site = "https://demo.data.gouv.fr"

config :transport,
  datagouvfr_site: datagouvfr_site,
  s3_buckets: %{
    history: "resource-history-dev",
    on_demand_validation: "on-demand-validation-dev",
    gtfs_diff: "gtfs-diff-dev",
    logos: "logos-dev",
    aggregates: "aggregates-dev"
  }

config :oauth2, Datagouvfr.Authentication,
  site: datagouvfr_site,
  redirect_uri: "http://localhost:5000/login/callback"

# Allows emails to be read at localhost:5000/dev/mailbox
# Add a dev.secret.exs to use a real email provider
config :transport, Transport.Mailer, adapter: Swoosh.Adapters.Local

extra_config_file = Path.join(__DIR__, "#{config_env()}.secret.exs")

if File.exists?(extra_config_file) do
  import_config extra_config_file
else
  require Logger

  Logger.warning(
    "Only the most basic features will work. Please create #{extra_config_file} based on config/dev.secret.template.exs for more advanced use."
  )
end

if File.exists?(".envrc") do
  Mix.raise("The .envrc file is deprecated and must be removed")
end
