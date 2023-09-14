defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

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
      conn
      |> post(contact_path(conn, :send_feedback, %{feedback: %{email: "spammer@internet.com", name: "John Doe"}}))
      |> get_flash(:info)
      # only spammers get a fox emoji in their flash message
      |> Kernel.=~("🦊")
      |> assert

      assert_no_email_sent()
    end

    test "Post feedback form without honey pot", %{conn: conn} do
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

      assert_email_sent(
        from: {"Formulaire feedback", "contact@transport.beta.gouv.fr"},
        to: "contact@transport.beta.gouv.fr",
        subject: "Nouvel avis pour on-demand-validation : j’aime",
        text_body:
          "Vous avez un nouvel avis sur le PAN.\nFonctionnalité : on-demand-validation\nNotation : j’aime\nAdresse e-mail : \n\nExplication : so useful for my GTFS files\n",
        html_body: nil,
        reply_to: "contact@transport.beta.gouv.fr"
      )
    end

    test "Post invalid parameters to feedback endpoint and check it doesn’t crash", %{conn: conn} do
      {conn, logs} =
        with_log(fn ->
          conn
          |> post(contact_path(conn, :send_feedback, %{topic: "question", demande: "where is my dataset?"}))
        end)

      assert redirected_to(conn, 302) == "/"
      assert logs =~ "Bad parameters for feedback"
      assert_no_email_sent()
    end
  end
end
