defmodule TransportWeb.Live.FeedbackLive do
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.InputHelpers
  import TransportWeb.Gettext
  require Logger

  @moduledoc """
  A reusable module to display a feedback form for a given feature, you can display inside a normal view or a live view.
  In case of normal view, don’t forget to add the app.js script with LiveView js inside the page as if it is not included in the general layout.
  If you add feedback for a new feature, add it to the list of features.
  """

  @feedback_rating_values DB.Feedback.ratings() |> Enum.map(&Atom.to_string/1)
  @feedback_features DB.Feedback.features() |> Enum.map(&Atom.to_string/1)

  def mount(_params, %{"feature" => feature, "locale" => locale, "csp_nonce_value" => nonce} = session, socket)
      when feature in @feedback_features do
    current_email = session |> get_in(["current_user", "email"])
    form = %DB.Feedback{} |> DB.Feedback.changeset(%{email: current_email, feature: feature}) |> to_form()

    socket =
      socket
      |> assign(
        nonce: nonce,
        form: form,
        feedback_sent: false,
        feedback_error: false
      )

    Gettext.put_locale(locale)

    {:ok, socket}
  end

  def handle_event("submit", %{"feedback" => %{"name" => name, "email" => email}}, socket) when name !== "" do
    # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Feedback coming from #{email} has been discarded because it filled the feedback form honeypot")
    # spammer get a little fox emoji in their flash message, useful for testing purpose
    {:noreply, socket |> assign(:feedback_sent, true)}
  end

  def handle_event(
        "submit",
        %{
          "feedback" =>
            %{"rating" => rating, "feature" => feature} =
              feedback_params
        },
        socket
      )
      when rating in @feedback_rating_values and feature in @feedback_features do
    changeset = %DB.Feedback{} |> DB.Feedback.changeset(feedback_params)

    with {:ok, feedback} <- DB.Repo.insert(changeset),
         {:ok, _} <- deliver_mail(feedback) do
      {:noreply, socket |> assign(:feedback_sent, true)}
    else
      _error ->
        {:noreply, socket |> assign(:feedback_error, true)}
    end
  end

  def handle_event("submit", session, socket) do
    Logger.error("Bad parameters for feedback #{inspect(session)}")
    {:noreply, socket |> assign(:feedback_error, true)}
  end

  @spec deliver_mail(DB.Feedback.t()) :: {:ok, term} | {:error, term}
  defp deliver_mail(feedback) do
    feedback_email =
      TransportWeb.ContactEmail.feedback(feedback.rating, feedback.explanation, feedback.email, feedback.feature)

    Transport.Mailer.deliver(feedback_email)
  end
end
