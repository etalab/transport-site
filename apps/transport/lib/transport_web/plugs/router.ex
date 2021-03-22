defmodule TransportWeb.Plugs.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  match(_, host: "proxy.", to: Unlock.Router)
  match("/api/*_", to: TransportWeb.API.Router)
  match("/gbfs/*_", to: GBFS.Router)
  match(_, to: TransportWeb.Router)
end
