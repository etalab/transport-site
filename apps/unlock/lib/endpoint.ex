# NOTE: required for tests, but not used in the actually app (the main app endpoint
# branches into Unlock.Router directly)
defmodule Unlock.Endpoint do
  use Phoenix.Endpoint, otp_app: :unlock

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Logger)
  plug(Plug.Head)

  plug(Unlock.Router)
end
