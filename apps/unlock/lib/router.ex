defmodule Unlock.Router do
  use Phoenix.Router

  get("/", Unlock.Controller, :index)
  get("/resource/:id", Unlock.Controller, :fetch, as: :resource)
end
