defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import Swoosh.TestAssertions

  test "Post contact form with honey pot filled", %{conn: conn} do
    conn
    |> post(contact_path(conn, :send_mail, %{email: "spammer@internet.com", name: "John Doe"}))
    |> get_flash(:info)
    # only spammers get a fox emoji in their flash message
    |> Kernel.=~("🦊")
    |> assert

    assert_no_email_sent()
  end

  test "Post contact form without honey pot", %{conn: conn} do
    conn
    |> post(
      contact_path(conn, :send_mail, %{email: "human@user.fr", topic: "dataset", question: "where is my dataset?"})
    )
    |> get_flash(:info)
    |> Kernel.=~("🦊")
    |> refute

    assert_email_sent(
      from: {"PAN, Formulaire Contact", "contact@transport.beta.gouv.fr"},
      to: "contact@transport.beta.gouv.fr",
      subject: "dataset",
      text_body: "where is my dataset?",
      html_body: nil,
      reply_to: "human@user.fr"
    )
  end
end
