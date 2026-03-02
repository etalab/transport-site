defmodule Transport.Test.Transport.Jobs.WarnUserInactivityJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.WarnUserInactivityJob

  doctest WarnUserInactivityJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  # 2 years + 1 month
  @inactivity_limit 30 * 25

  test "prune a single contact" do
    now = DateTime.utc_now()
    insert_contact_inactive_since(now, %{days: @inactivity_limit + 10})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_no_email_sent()

    assert 0 == DB.Repo.aggregate(DB.Contact, :count)
  end

  @login_prompt ~r/Pour conserver votre compte, il vous suffira de <a href="https?:\/\/[^\\]+\/login\/explanation\?redirect_path=%2F">vous reconnecter<\/a>./

  test "warn first time 30 days before deadline" do
    now = DateTime.utc_now()
    %DB.Contact{} = insert_contact_inactive_since(now, %{days: @inactivity_limit - 31})
    %DB.Contact{} = contact = insert_contact_inactive_since(now, %{days: @inactivity_limit - 30})
    %DB.Contact{} = insert_contact_inactive_since(now, %{days: @inactivity_limit - 29})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_warning_is_sent(contact, "Votre compte sera supprimé dans 1 mois", [
      "Vous avez un compte utilisateur associé à l‘adresse email <strong>#{contact.email}</strong> sur <a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>.",
      "Dans 1 mois nous supprimerons votre compte conformément aux règles en vigueur concernant les données utilisateur.",
      @login_prompt
    ])

    assert 3 == DB.Repo.aggregate(DB.Contact, :count)
  end

  test "warn first time 15 days before deadline" do
    now = DateTime.utc_now()
    %DB.Contact{} = insert_contact_inactive_since(now, %{days: @inactivity_limit - 14})

    %DB.Contact{id: contact_id, email: email} =
      contact = insert_contact_inactive_since(now, %{days: @inactivity_limit - 15})

    %DB.Contact{} = insert_contact_inactive_since(now, %{days: @inactivity_limit - 16})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_warning_is_sent(contact, "Votre compte sera supprimé dans 2 semaines", [
      "Vous avez un compte utilisateur associé à l‘adresse email <strong>#{contact.email}</strong> sur <a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>.",
      "Dans 2 semaines nous supprimerons votre compte conformément aux règles en vigueur concernant les données utilisateur.",
      @login_prompt
    ])

    assert 3 == DB.Repo.aggregate(DB.Contact, :count)

    assert [
             %DB.Notification{
               reason: :warn_user_inactivity,
               role: :reuser,
               contact_id: ^contact_id,
               email: ^email,
               payload: %{"horizon" => 15},
               notification_subscription_id: nil
             }
           ] = DB.Notification |> DB.Repo.all()
  end

  test "warn first time the day before deadline" do
    now = DateTime.utc_now()
    %DB.Contact{} = insert_contact_inactive_since(now, %{days: @inactivity_limit - 2})

    %DB.Contact{id: contact_id, email: email} =
      contact = insert_contact_inactive_since(now, %{days: @inactivity_limit - 1})

    %DB.Contact{} = insert_contact_inactive_since(now, %{days: @inactivity_limit})

    assert :ok == perform_job(WarnUserInactivityJob, %{})

    assert_warning_is_sent(contact, "Votre compte sera supprimé demain", [
      "Vous avez un compte utilisateur associé à l‘adresse email <strong>#{contact.email}</strong> sur <a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>.",
      "Demain nous supprimerons votre compte conformément aux règles en vigueur concernant les données utilisateur.",
      @login_prompt
    ])

    assert 2 == DB.Repo.aggregate(DB.Contact, :count)

    assert [
             %DB.Notification{
               reason: :warn_user_inactivity,
               role: :reuser,
               contact_id: ^contact_id,
               email: ^email,
               payload: %{"horizon" => 1},
               notification_subscription_id: nil
             }
           ] = DB.Notification |> DB.Repo.all()
  end

  defp insert_contact_inactive_since(now, %{days: days}) do
    last_login_at = DateTime.add(now, 0 - days, :day)

    insert_contact(%{last_login_at: last_login_at})
  end

  defp assert_warning_is_sent(%DB.Contact{email: email} = contact, subject, body_parts) do
    contact_name = DB.Contact.display_name(contact)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^contact_name, ^email}],
                           reply_to: {"", "contact@transport.data.gouv.fr"},
                           subject: ^subject,
                           text_body: nil,
                           html_body: html_body
                         } ->
      Enum.each(body_parts, fn body_part ->
        assert simplify_whitespaces(html_body) =~ body_part
      end)
    end)
  end

  defp simplify_whitespaces(str), do: String.replace(str, ~r/\s/, " ")
end
