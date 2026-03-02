defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import Swoosh.TestAssertions

  setup do
    on_exit(fn -> assert_no_email_sent() end)
  end

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
        contact_path(conn, :send_mail, %{
          email: "human@user.fr",
          user_type: "data-reuser",
          question_type: "other",
          subject: "dataset",
          question: "where is my dataset?"
        })
      )

    refute Phoenix.Flash.get(conn.assigns.flash, :info) =~ "🦊"

    assert_email_sent(fn %Swoosh.Email{
                           from: {"PAN, Formulaire Contact", "contact@transport.data.gouv.fr"},
                           to: [{"", "contact@transport.data.gouv.fr"}],
                           subject: "dataset",
                           text_body: nil,
                           html_body: html,
                           reply_to: {"", "human@user.fr"}
                         } ->
      assert html =~ "where is my dataset?"
    end)
  end
end
