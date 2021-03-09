defmodule Proxy.Router do
  use Phoenix.Router

  scope "/proxy" do
    get "/", Proxy.Controller, :get
  end
end
