defmodule Proxy.Endpoint do
  use Phoenix.Endpoint, otp_app: :proxy

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  # TODO: review items here
  plug(Plug.RequestId)
  plug(Plug.Logger)
  plug(Plug.Head)

  plug(Proxy.Router)
end
