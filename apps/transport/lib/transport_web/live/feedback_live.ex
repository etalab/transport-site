defmodule TransportWeb.Live.FeedbackLive do
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.InputHelpers
  import TransportWeb.Gettext



  def mount(_params, %{"feature" => feature} = session, socket) do
    IO.inspect(socket)
    current_email = session |> get_in(["current_user", "email"])
    IO.inspect(session)
    {:ok, socket |> assign(feature: feature, current_email: current_email) }
  end


end
