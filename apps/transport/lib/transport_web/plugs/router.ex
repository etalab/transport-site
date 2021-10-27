defmodule TransportWeb.Plugs.Router do
  use Plug.Router

  # if the application is in worker mode, routing stops here
  plug(TransportWeb.Plugs.Worker)

  plug(:match)
  plug(:dispatch)

  # Technically, we should probably route to the Unlock.Endpoint
  # but because the current file is very deep in the pipeline at
  # the moment, this would mean double logging etc. The Unlock.Endpoint
  # is as a consequence not used, except for testing!
  match(_, host: "proxy.", to: Unlock.Router)
  match("/api/*_", to: TransportWeb.API.Router)
  match("/gbfs/*_", to: GBFS.Router)
  match(_, to: TransportWeb.Router)
end
