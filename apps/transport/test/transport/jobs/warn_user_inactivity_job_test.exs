defmodule Transport.Test.Transport.Jobs.WarnUserInactivityJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.WarnUserInactivityJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "prune a single contact" do
    prunable = DateTime.utc_now() |> DateTime.add(-400, :day)

    %DB.Contact{id: pruned_contact_id} = insert_contact(%{last_login_at: prunable})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert nil == DB.Repo.get(DB.Contact, pruned_contact_id)
  end

  test "warn first time 30 days before deadline" do
    %DB.Contact{email: _} = insert_contact_inactive_since(%{days: 359})
    %DB.Contact{email: email} = insert_contact_inactive_since(%{days: 360})
    %DB.Contact{email: _} = insert_contact_inactive_since(%{days: 361})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_warning_is_sent(email, "Votre compte sera supprimé dans 1 mois", [
      "Vous avez un compte utilisateur associé à l‘adresse email <strong>#{email}</strong> sur <a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>.",
      "Dans 1 mois nous supprimerons votre compte conformément aux règles en vigueur concernant les données utilisateur."
    ])
  end

  test "warn first time 15 days before deadline" do
    %DB.Contact{email: _} = insert_contact_inactive_since(%{days: 374})
    %DB.Contact{email: email} = insert_contact_inactive_since(%{days: 375})
    %DB.Contact{email: _} = insert_contact_inactive_since(%{days: 376})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_warning_is_sent(email, "Votre compte sera supprimé dans 2 semaines", [
      "Vous avez un compte utilisateur associé à l‘adresse email <strong>#{email}</strong> sur <a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>.",
      "Dans 2 semaines nous supprimerons votre compte conformément aux règles en vigueur concernant les données utilisateur."
    ])
  end

  test "warn first time the day before deadline" do
    %DB.Contact{email: _} = insert_contact_inactive_since(%{days: 388})
    %DB.Contact{email: email} = insert_contact_inactive_since(%{days: 389})
    %DB.Contact{email: _} = insert_contact_inactive_since(%{days: 390})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_warning_is_sent(email, "Votre compte sera supprimé demain", [
      "Vous avez un compte utilisateur associé à l‘adresse email <strong>#{email}</strong> sur <a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>.",
      "Demain nous supprimerons votre compte conformément aux règles en vigueur concernant les données utilisateur."
    ])
  end

  defp insert_contact_inactive_since(%{days: days}) do
    last_login_at = DateTime.utc_now() |> DateTime.add(0 - days, :day)

    insert_contact(%{last_login_at: last_login_at})
  end

  defp assert_warning_is_sent(email, subject, body_parts) do
    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_email_sent(fn %Swoosh.Email{} = sent ->
      assert %Swoosh.Email{
               from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
               to: [{"", ^email}],
               reply_to: {"", "contact@transport.data.gouv.fr"},
               subject: ^subject,
               text_body: nil,
               html_body: html_body
             } = sent

      Enum.each(body_parts, fn body_part ->
        assert simplify_whitespaces(html_body) =~ body_part
      end)
    end)
  end

  defp simplify_whitespaces(str), do: String.replace(str, ~r/\s/, " ")
end
