defmodule TransportWeb.ContactController do
  use TransportWeb, :controller
  alias Transport.Mailgun.Client

  def send_mail(%Plug.Conn{} = conn, params) do
    case Client.send_mail(params["email"], params["demande"]) do
      {:ok, body} ->
        case conn.req_headers do
          [{"accept", "application/json"}] ->
            render conn, "send_mail.json", body: body
          _ ->
            conn
            |> put_flash(:info, dgettext("contact", "Message sent, we will contact you soon."))
            |> redirect(to: page_path(conn, :index))
        end
      {:error, _} -> render(conn, ErrorView, "500.html")
    end
  end

  def form(%Plug.Conn{} = conn, _params) do
    render conn, "form.html"
  end

end
