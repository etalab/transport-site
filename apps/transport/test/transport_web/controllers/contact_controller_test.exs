defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import Swoosh.TestAssertions

  test "Post contact form with honey pot filled", %{conn: conn} do
    conn = post(conn, contact_path(conn, :send_mail, %{email: "spammer@internet.com", name: "John Doe"}))
    # only spammers get a fox emoji in their flash message
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "🦊"

    assert_no_email_sent()
  end

  test "Post contact form without honey pot", %{conn: conn} do
    conn =
      conn
      |> post(
        contact_path(conn, :send_mail, %{email: "human@user.fr", topic: "dataset", question: "where is my dataset?"})
      )

    refute Phoenix.Flash.get(conn.assigns.flash, :info) =~ "🦊"

    assert_email_sent(
      from: {"PAN, Formulaire Contact", "contact@transport.data.gouv.fr"},
      to: "contact@transport.data.gouv.fr",
      subject: "dataset",
      text_body: "where is my dataset?",
      html_body: nil,
      reply_to: "human@user.fr"
    )
  end
end
