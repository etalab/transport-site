defmodule TransportWeb.Plugs.Router do
  use Plug.Router

  plug(TransportWeb.Plugs.HealthCheck, at: "/health-check")
  plug(TransportWeb.Plugs.WorkerHealthcheck, if: {Transport.Application, :worker_only?})

  plug(:match)
  plug(:dispatch)

  # Technically, we should probably route to the Unlock.Endpoint
  # but because the current file is very deep in the pipeline at
  # the moment, this would mean double logging etc. The Unlock.Endpoint
  # is as a consequence not used, except for testing!
  match(_, host: "proxy.", to: Unlock.Router)
  match("/api/*_", to: TransportWeb.API.Router)
  match(_, to: TransportWeb.Router)
end
