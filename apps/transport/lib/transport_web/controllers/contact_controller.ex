defmodule TransportWeb.ContactController do
  use TransportWeb, :controller
  require Logger
  @feedback_rating_values ["like", "neutral", "dislike"]
  @feedback_features ["gtfs-stops", "on-demand-validation", "gbfs-validation"]

  @spec send_mail(Plug.Conn.t(), map()) :: {:error, any} | Plug.Conn.t()
  def send_mail(conn, %{"email" => email, "name" => name} = params) when name !== "" do
    # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Mail coming from #{email} has been discarded because it filled the contact form honeypot")

    conn
    # spammer get a little fox emoji in their flash message, useful for testing purpose
    |> put_flash(:info, "Your email has been sent, we will contact you soon 🦊")
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end

  def send_mail(conn, %{"email" => email, "topic" => subject, "question" => question} = params) do
    [email, subject, question] = sanitize_inputs([email, subject, question])
    contact_email = TransportWeb.ContactEmail.contact(email, subject, question)

    case Transport.Mailer.deliver(contact_email) do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("Your email has been sent, we will contact you soon"))
        |> redirect(to: params["redirect_path"] || page_path(conn, :index))

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("There has been an error, try again later"))
        |> redirect(to: params["redirect_path"] || page_path(conn, :index))
    end
  end

  def send_mail(conn, params) do
    Logger.error("Bad parameters for sending email #{inspect(params)}")

    conn
    |> put_flash(:error, gettext("There has been an error, try again later"))
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end

  def send_feedback(conn, %{"feedback" => %{"name" => name, "email" => email}}) when name !== "" do
    # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Feedback coming from #{email} has been discarded because it filled the feedback form honeypot")

    conn
    # spammer get a little fox emoji in their flash message, useful for testing purpose
    |> put_flash(:info, "Your feedback has been sent, we will contact you soon 🦊")
    |> redirect(to: page_path(conn, :index))
  end

  def send_feedback(
        conn,
        %{"feedback" => %{"rating" => rating, "explanation" => explanation, "email" => email, "feature" => feature}}
      )
      when rating in @feedback_rating_values and feature in @feedback_features do
    [email, explanation] = sanitize_inputs([email, explanation])

    feedback_email = TransportWeb.ContactEmail.feedback(rating, explanation, email, feature)

    case Transport.Mailer.deliver(feedback_email) do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("Thanks for your feedback!"))
        |> redirect(to: page_path(conn, :index))

      {:error, message} ->
        Logger.error("Error while sending feedback: #{message}")

        conn
        |> put_flash(:error, gettext("There has been an error, try again later"))
        |> redirect(to: page_path(conn, :index))
    end
  end

  def send_feedback(conn, params) do
    Logger.error("Bad parameters for feedback #{inspect(params)}")

    conn
    |> put_flash(:error, gettext("There has been an error, try again later"))
    |> redirect(to: page_path(conn, :index))
  end

  defp sanitize_inputs(arr) do
    arr |> Enum.map(&String.trim/1) |> Enum.map(&HtmlSanitizeEx.strip_tags/1)
  end
end

defmodule TransportWeb.ContactEmail do
  import Swoosh.Email

  def contact(email, subject, question) do
    new()
    |> from({"PAN, Formulaire Contact", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(email)
    |> subject(subject)
    |> text_body(question)
  end

  def feedback(rating, explanation, email, feature) do
    rating_t = %{"like" => "j’aime", "neutral" => "neutre", "dislike" => "mécontent"}

    reply_email =
      if email == "" do
        Application.fetch_env!(:transport, :contact_email)
      else
        email
      end

    feedback_content = """
    Vous avez un nouvel avis sur le PAN.
    Fonctionnalité : #{feature}
    Notation : #{rating_t[rating]}
    Adresse e-mail : #{email}

    Explication : #{explanation}
    """

    new()
    |> from({"Formulaire feedback", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(reply_email)
    |> subject("Nouvel avis pour #{feature} : #{rating_t[rating]}")
    |> text_body(feedback_content)
  end
end
