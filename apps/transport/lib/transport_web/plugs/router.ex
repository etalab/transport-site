defmodule TransportWeb.Plugs.Router do
  use Plug.Router

  plug(TransportWeb.Plugs.HealthCheck, at: "/health-check")
  plug(TransportWeb.Plugs.WorkerHealthcheck, if: {Transport.Application, :worker_only?})

  plug(:match)
  plug(:dispatch)

  match(_, host: "proxy.", to: Unlock.Router)
  match("/api/*_", to: TransportWeb.API.Router)
  match(_, to: TransportWeb.Router)
end
