defmodule GBFS.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :gbfs

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Sentry.PlugContext)

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  plug(Plug.Session,
    store: :cookie,
    key: "_gbfs_key",
    signing_salt: "ZCNY1rhw"
  )

  plug(GBFS.Router)
end
