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

  def send_mail(conn, %{"email" => email, "topic" => subject, "question" => question} = params) do
    %{email: email, subject: subject, question: question} =
      sanitize_inputs(%{email: email, subject: subject, question: question})

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

  defp sanitize_inputs(map), do: Map.new(map, fn {k, v} -> {k, v |> String.trim() |> HtmlSanitizeEx.strip_tags()} end)
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
    rating_t = %{like: "j’aime", neutral: "neutre", dislike: "mécontent"}

    reply_email = if email, do: email, else: Application.fetch_env!(:transport, :contact_email)

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
