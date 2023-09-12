defmodule TransportWeb.ContactController do
  use TransportWeb, :controller
  require Logger

  @spec send_mail(Plug.Conn.t(), map()) :: {:error, any} | Plug.Conn.t()
  def send_mail(conn, %{"email" => email, "name" => name} = params) when name !== "" do
    # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Mail coming from #{email} has been discarded because it filled the contact form honeypot")

    conn
    # spammer get a little fox emoji in their flash message, useful for testing purpose
    |> put_flash(:info, "Your email has been sent, we will contact you soon 🦊")
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end

  def send_mail(conn, %{"email" => email, "topic" => subject, "demande" => demande} = params) do
    case Transport.EmailSender.impl().send_mail(
           "PAN, Formulaire Contact",
           Application.get_env(:transport, :contact_email),
           Application.get_env(:transport, :contact_email),
           email,
           subject,
           demande,
           ""
         ) do
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

  def send_feedback(conn, %{"feedback" => %{"name" => name, "email" => email}} = params) when name !== "" do
    # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Feedback coming from #{email} has been discarded because it filled the feedback form honeypot")

    conn
    # spammer get a little fox emoji in their flash message, useful for testing purpose
    |> put_flash(:info, "Your feedback has been sent, we will contact you soon 🦊")
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end

  def send_feedback(
        conn,
        %{"feedback" => %{"rating" => rating, "explanation" => explanation, "email" => email, "feature" => feature}}
      )
      when rating in ["like", "neutral", "dislike"] and
             feature in ["gtfs-stops", "on-demand-validation", "gbfs-validation"] do
    [email, explanation] = [email, explanation] |> Enum.map(&String.trim/1)

    rating_t = %{"like" => "j’aime", "neutral" => "neutre", "dislike" => "mécontent"}

    feedback_content = """
    Vous avez un nouvel avis sur le PAN.
    Fonctionnalité: #{feature}
    Notation: #{rating_t[rating]}
    Adresse email: #{email}

    Explication: #{explanation}
    """

    reply_email =
      if email == "" do
        Application.get_env(:transport, :contact_email)
      else
        email
      end

    case Transport.EmailSender.impl().send_mail(
           "PAN, Formulaire Feedback",
           Application.get_env(:transport, :contact_email),
           Application.get_env(:transport, :contact_email),
           reply_email,
           "Nouvel avis pour #{feature}: #{rating_t[rating]}",
           feedback_content,
           ""
         ) do
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
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end
end
