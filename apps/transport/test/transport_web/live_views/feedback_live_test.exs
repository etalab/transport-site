defmodule TransportWeb.FeedbackLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!

  @endpoint TransportWeb.Endpoint

  test "Render the feedback component", %{conn: conn} do
    {:ok, _view, html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive, session: %{"feature" => "my-feature", "locale" => "fr"})

    assert html =~ "Qu’avez-vous pensé de cette page ?"
  end

  test "Post feedback form with honey pot filled", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive,
        session: %{"feature" => "on-demand-validation", "locale" => "fr"}
      )

    view
    |> element("form")
    |> render_submit(%{feedback: %{email: "spammer@internet.com", name: "John Doe"}})
    |> Kernel.=~("Merci d’avoir laissé votre avis !")
    |> assert

    assert_no_email_sent()
  end

  test "Post feedback form without honey pot", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive,
        session: %{"feature" => "on-demand-validation", "locale" => "fr"}
      )

    view
    |> element("form")
    |> render_submit(%{
      feedback: %{
        email: "",
        feature: "on-demand-validation",
        rating: "like",
        explanation: "so useful for my GTFS files"
      }
    })
    |> Kernel.=~("Merci d’avoir laissé votre avis !")
    |> assert

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

  test "Post invalid parameters in feedback form and check it doesn’t crash", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive,
        session: %{"feature" => "on-demand-validation", "locale" => "fr"}
      )

    {view, logs} =
      with_log(fn ->
        view
        |> element("form")
        |> render_submit(%{topic: "question", demande: "where is my dataset?"})
      end)

    assert view =~ "Il y a eu une erreur réessayez."

    assert logs =~ "Bad parameters for feedback"

    assert_no_email_sent()
  end

  test "Is correctly included in the validation Liveview", %{conn: conn} do
    Transport.Shared.Schemas.Mock |> expect(:transport_schemas, 2, fn -> %{} end)
    {:ok, _view, html} = conn |> live(live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive))
    assert html =~ "<h2>Laissez-nous votre avis</h2>"
  end
end
