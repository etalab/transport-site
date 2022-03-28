defmodule TransportWeb.Presence do
  use Phoenix.Presence,
    otp_app: :transport,
    pubsub_server: TransportWeb.PubSub

  @moduledoc """
  A "Presence" (user tracking) module for the app.
  """
end
