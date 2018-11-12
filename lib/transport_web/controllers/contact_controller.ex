defmodule TransportWeb.ContactController do
  use TransportWeb, :controller
  alias Transport.Mailjet.Client

  def send_mail(conn, params) do
    case Client.send_mail(params["email"], params["demande"]) do
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

end
