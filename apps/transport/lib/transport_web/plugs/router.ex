defmodule TransportWeb.Plugs.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  match("/api/*_", to: TransportWeb.API.Router)
  match("/gbfs/*_", to: GBFS.Router)
  # NOTE: it would be better to serve this under a subdomain in production.
  match("/proxy/*_", to: Proxy.Router)
  match(_, to: TransportWeb.Router)
end
