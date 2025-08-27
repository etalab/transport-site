defmodule Unlock.Router do
  use Phoenix.Router

  pipeline :api do
    plug(CORSPlug, origin: "*", expose: ["*"], credentials: false)
    plug(TransportWeb.Plugs.AppSignalFilter)
    plug(Unlock.Plugs.TokenAuth)
  end

  scope "/" do
    pipe_through(:api)

    get("/", Unlock.Controller, :index)
    get("/resource/:id", Unlock.Controller, :fetch, as: :resource)
    post("/resource/:id", Unlock.Controller, :fetch, as: :resource)
  end
end
