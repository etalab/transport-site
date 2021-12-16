defmodule Unlock.Router do
  use Phoenix.Router

  pipeline :api do
    plug(CORSPlug, origin: "*", expose: ["*"])
  end

  scope "/" do
    pipe_through(:api)

    get("/", Unlock.Controller, :index)
    get("/resource/:id", Unlock.Controller, :fetch, as: :resource)
  end
end
