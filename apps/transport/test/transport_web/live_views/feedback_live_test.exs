defmodule TransportWeb.FeedbackLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  @endpoint TransportWeb.Endpoint

  test "Render the feedback component", %{conn: conn} do
    {:ok, _view, html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive,
        session: %{"feature" => "on_demand_validation", "locale" => "fr", "csp_nonce_value" => Ecto.UUID.generate()}
      )

    assert html =~ "Qu’avez-vous pensé de cette page ?"
  end

  test "Post feedback form with honey pot filled", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive,
        session: %{"feature" => "on_demand_validation", "locale" => "fr", "csp_nonce_value" => Ecto.UUID.generate()}
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
        session: %{"feature" => "on_demand_validation", "locale" => "fr", "csp_nonce_value" => Ecto.UUID.generate()}
      )

    view
    |> element("form")
    |> render_submit(%{
      feedback: %{
        email: "",
        feature: "on_demand_validation",
        rating: "like",
        explanation: "  so useful for my GTFS files  "
      }
    })
    |> Kernel.=~("Merci d’avoir laissé votre avis !")
    |> assert

    assert_email_sent(fn %Swoosh.Email{
                           from: {"Formulaire feedback", "contact@transport.data.gouv.fr"},
                           to: [{"", "contact@transport.data.gouv.fr"}],
                           subject: "Nouvel avis pour on_demand_validation : j’aime",
                           text_body: nil,
                           html_body: html,
                           reply_to: {"", "contact@transport.data.gouv.fr"}
                         } ->
      assert remove_whitespace(html) =~
               "<p> Vous avez un nouvel avis sur le PAN.</p> <ul> <li> Fonctionnalité : on_demand_validation </li> <li> Notation : j’aime </li> <li> Adresse e-mail : </li> </ul> <p> Explication : so useful for my GTFS files</p>"
    end)

    assert %DB.UserFeedback{
             rating: :like,
             explanation: "so useful for my GTFS files",
             feature: :on_demand_validation,
             email: nil
           } = DB.UserFeedback |> Ecto.Query.last() |> DB.Repo.one()
  end

  test "Post invalid parameters in feedback form and check it doesn’t crash", %{conn: conn} do
    feedback_count = DB.UserFeedback |> DB.Repo.aggregate(:count, :id)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FeedbackLive,
        session: %{"feature" => "on_demand_validation", "locale" => "fr", "csp_nonce_value" => Ecto.UUID.generate()}
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
    # Nothing should have been inserted in the database
    assert feedback_count == DB.UserFeedback |> DB.Repo.aggregate(:count, :id)
  end

  test "Is correctly included in the validation Liveview", %{conn: conn} do
    Transport.Shared.Schemas.Mock |> expect(:transport_schemas, 2, fn -> %{} end)
    {:ok, _view, html} = conn |> live(live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive))
    assert html =~ "<h2>Laissez-nous votre avis</h2>"
  end

  defp remove_whitespace(value), do: value |> String.replace(~r/(\s)+/, " ") |> String.trim()
end
