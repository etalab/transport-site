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
    Logger.error("Bad parameters for sending email #{params}")

    conn
    |> put_flash(:error, gettext("There has been an error, try again later"))
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end

  def send_feedback(conn, %{"feedback" => %{"name" => name, "email" => email}} = params) when name !== "" do
    # someone filled the honeypot field ("name") => discard as spam
    Logger.info("Mail coming from #{email} has been discarded because it filled the contact form honeypot")

    conn
    # spammer get a little fox emoji in their flash message, useful for testing purpose
    |> put_flash(:info, "Your email has been sent, we will contact you soon 🦊")
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end


  def send_feedback(conn, %{"feedback" => %{"rating" => rating, "explanation" => explanation, "email" => email}} = params) do
    # IO.inspect(params)
    # send_resp(conn, 201, "good")

    feedback_content = "Vous avez un nouvel avis sur le PAN!\nNotation: #{rating}\n#{explanation}"

    case Transport.EmailSender.impl().send_mail(
           "PAN, Formulaire Feedback",
           Application.get_env(:transport, :contact_email),
           Application.get_env(:transport, :contact_email),
           email,
           "Nouveau feedback: #{rating}",
           feedback_content,
           ""
         ) do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("Thanks for your feedback!"))
        |> redirect(to: params["redirect_path"] || page_path(conn, :index))

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("There has been an error, try again later"))
        |> redirect(to: params["redirect_path"] || page_path(conn, :index))
    end
  end

  def send_feedback(conn, params) do
    Logger.error("Bad parameters for feedback #{params}")

    conn
    |> put_flash(:error, gettext("There has been an error, try again later"))
    |> redirect(to: params["redirect_path"] || page_path(conn, :index))
  end

end
