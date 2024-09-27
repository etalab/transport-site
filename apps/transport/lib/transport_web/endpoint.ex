defmodule TransportWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :transport

  @session_options [
    store: :cookie,
    key: "_transport_key",
    signing_salt: "wqoqbzqj",
    same_site: "Lax",
    # 15 days
    max_age: 24 * 60 * 60 * 15
  ]

  socket("/socket", TransportWeb.UserSocket)
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :transport,
    gzip: Mix.env() == :prod,
    only: TransportWeb.static_paths()
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(RemoteIp, headers: ["x-forwarded-for"])
  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [
      :urlencoded,
      :json,
      {:multipart, length: 200_000_000}
    ],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Sentry.PlugContext)

  plug(Plug.MethodOverride)
  plug(TransportWeb.Plugs.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(Plug.Session, @session_options)

  plug(TransportWeb.Plugs.Router)
end
