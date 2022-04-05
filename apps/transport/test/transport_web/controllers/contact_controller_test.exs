defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import Mox
  setup :verify_on_exit!

  test "Post contact form with honey pot filled", %{conn: conn} do
    Transport.EmailSender.Mock
    |> expect(:send_mail, 0, fn(_, _, _, _, _, _, _) -> nil end)

    conn
    |> post(contact_path(conn, :send_mail, %{email: "spammer@internet.com", name: "John Doe"}))
    |> get_flash(:info)
    # only spammers get a fox emoji in their flash message
    |> Kernel.=~("🦊")
    |> assert
  end

  test "Post contact form without honey pot", %{conn: conn} do
    Transport.EmailSender.Mock
    |> expect(:send_mail, fn from_name, from_email, to_email, reply_to, topic, text_body, html_body ->
      assert %{
               from_name: from_name,
               from_email: from_email,
               to_email: to_email,
               topic: topic,
               text_body: text_body,
               html_body: html_body,
               reply_to: reply_to
             } == %{
               from_name: "PAN, Formulaire Contact",
               from_email: "contact@transport.beta.gouv.fr",
               to_email: "contact@transport.beta.gouv.fr",
               topic: "question",
               text_body: "where is my dataset?",
               html_body: "",
               reply_to: "human@user.fr"
             }

      {:ok, text_body}
    end)

    conn
    |> post(
      contact_path(conn, :send_mail, %{email: "human@user.fr", topic: "question", demande: "where is my dataset?"})
    )
    |> get_flash(:info)
    |> case do
      nil -> assert true
      msg -> refute msg =~ "🦊"
    end
  end
end
