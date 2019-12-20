defmodule TransportWeb.ContactController do
  use TransportWeb, :controller
  alias Mailjet.Client
  require Logger

  def send_mail(conn, %{"email" => email, "topic" => topic, "demande" => demande} = params) do
    case Client.send_mail("PAN, Formulaire Contact", "contact@transport.beta.gouv.fr", email, topic, demande) do
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

  def send_mail(_, params), do: Logger.error("Bad parameters for sending email #{params}")
end
