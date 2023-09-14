defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import Mox
  import ExUnit.CaptureLog
  import Swoosh.TestAssertions
  setup :verify_on_exit!

  describe "contact form" do
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

  describe "feedback form" do
    test "Post feedback form with honey pot filled", %{conn: conn} do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> nil end)

      conn
      |> post(contact_path(conn, :send_feedback, %{feedback: %{email: "spammer@internet.com", name: "John Doe"}}))
      |> get_flash(:info)
      # only spammers get a fox emoji in their flash message
      |> Kernel.=~("🦊")
      |> assert
    end

    test "Post feedback form without honey pot", %{conn: conn} do
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "Formulaire feedback",
                               "contact@transport.beta.gouv.fr",
                               "contact@transport.beta.gouv.fr",
                               reply_to,
                               subject,
                               text_body,
                               "" ->
        assert subject == "Nouvel avis pour on-demand-validation : j’aime"

        assert text_body ==
                 "Vous avez un nouvel avis sur le PAN.\nFonctionnalité : on-demand-validation\nNotation : j’aime\nAdresse e-mail : \n\nExplication : so useful for my GTFS files\n"

        assert reply_to == "contact@transport.beta.gouv.fr"

        {:ok, :text_body}
      end)

      conn
      |> post(
        contact_path(conn, :send_feedback, %{
          feedback: %{
            email: "",
            feature: "on-demand-validation",
            rating: "like",
            explanation: "so useful for my GTFS files"
          }
        })
      )
      |> get_flash(:info)
      |> Kernel.=~("🦊")
      |> refute
    end

    test "Post invalid parameters to feedback endpoint and check it doesn’t crash", %{conn: conn} do
      {conn, logs} =
        with_log(fn ->
          conn
          |> post(contact_path(conn, :send_feedback, %{topic: "question", demande: "where is my dataset?"}))
        end)

      assert redirected_to(conn, 302) == "/"

      assert logs =~ "Bad parameters for feedback"
    end
  end
end
