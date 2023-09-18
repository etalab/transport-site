defmodule TransportWeb.Live.FeedbackLive do
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.InputHelpers
  import TransportWeb.Gettext
  require Logger


  @feedback_rating_values ["like", "neutral", "dislike"]
  @feedback_features ["gtfs-stops", "on-demand-validation", "gbfs-validation"]

  def mount(_params, %{"feature" => feature} = session, socket) do
    current_email = session |> get_in(["current_user", "email"])
    {:ok, socket |> assign(feature: feature, current_email: current_email, feedback_sent: false) }
  end

    def handle_event("submit", %{"feedback" => %{"name" => name, "email" => email}}, socket) when name !== "" do
        # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Feedback coming from #{email} has been discarded because it filled the feedback form honeypot")
    {:noreply, socket |> assign(:feedback_sent, true)}    # spammer get a little fox emoji in their flash message, useful for testing purpose
    end


  def handle_event("submit", %{"feedback" => %{"rating" => rating, "explanation" => explanation, "email" => email, "feature" => feature}}, socket)
  when rating in @feedback_rating_values and feature in @feedback_features do
    %{email: email, explanation: explanation} = sanitize_inputs(%{email: email, explanation: explanation})

    feedback_email = TransportWeb.ContactEmail.feedback(rating, explanation, email, feature)
    case Transport.Mailer.deliver(feedback_email) do
      {:ok, _} ->
        {:noreply, socket |> assign(:feedback_sent, true)}
      {:error, _} ->
        {:noreply, socket |> assign(:feedback_error, true)}
    end
  end

  def handle_event("submit", session, socket) do
    Logger.error("Bad parameters for sending feedback #{inspect(session)}")
    {:noreply, socket |> assign(:feedback_error, true)}
  end

  defp sanitize_inputs(map), do: Map.new(map, fn {k, v} -> {k, v |> String.trim() |> HtmlSanitizeEx.strip_tags()} end)


end
