defmodule TransportWeb.ContactController do
  use TransportWeb, :controller
  alias Transport.Mailgun.Client

  def send_mail(conn, params) do
    case Client.send_mail(params["email"], params["demande"]) do
      {:ok, body} -> render conn, "send_mail.json", body: body
      {:error, _} -> render(conn, ErrorView, "500.html")
    end
  end

end
