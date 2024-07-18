defmodule Transport.Test.Transport.Jobs.PromoteReuserSpaceJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.PromoteReuserSpaceJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    %DB.Contact{email: email, id: contact_id} = contact = insert_contact()
    assert :ok == perform_job(PromoteReuserSpaceJob, %{"contact_id" => contact_id})

    display_name = DB.Contact.display_name(contact)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, ^email}],
                           reply_to: {"", "contact@transport.data.gouv.fr"},
                           subject: "Gestion de vos favoris dans votre espace réutilisateur",
                           text_body: nil,
                           html_body: html_body
                         } ->
      assert html_body =~
               "Vous venez d’ajouter votre 1er favori pour suivre un jeu de données référencé sur le PAN et nous vous en félicitons !"

      assert html_body =~
               ~s(Rendez-vous sur votre <a href="http://127.0.0.1:5100/espace_reutilisateur?utm_source=transactional_email&amp;utm_medium=email&amp;utm_campaign=promote_reuser_space">Espace réutilisateur</a> pour personnaliser vos préférences)
    end)

    assert [
             %DB.Notification{
               reason: :promote_reuser_space,
               contact_id: ^contact_id,
               email: ^email,
               role: :reuser,
               dataset_id: nil,
               notification_subscription_id: nil
             }
           ] = DB.Notification |> DB.Repo.all()
  end
end
