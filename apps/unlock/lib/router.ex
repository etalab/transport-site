defmodule Unlock.Router do
  use Phoenix.Router

  get "/", Unlock.Controller, :get
end
