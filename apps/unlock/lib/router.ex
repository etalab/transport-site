defmodule Unlock.Router do
  use Phoenix.Router

  get "/", Unlock.Controller, :index
end
