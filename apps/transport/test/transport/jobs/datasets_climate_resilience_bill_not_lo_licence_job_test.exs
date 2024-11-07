defmodule Transport.Test.Transport.Jobs.DatasetsClimateResilienceBillNotLOLicenceJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.DatasetsClimateResilienceBillNotLOLicenceJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    dataset =
      insert(:dataset,
        is_active: true,
        custom_tags: ["foo", "loi-climat-resilience"],
        licence: "odc-odbl",
        custom_title: "Bar"
      )

    lo_dataset = insert(:dataset, is_active: true, custom_tags: ["foo", "loi-climat-resilience"], licence: "fr-lo")

    assert :ok == perform_job(DatasetsClimateResilienceBillNotLOLicenceJob, %{})

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: "contact@transport.data.gouv.fr",
      subject: "Jeux de données article 122 avec licence inappropriée",
      text_body: nil,
      html_body:
        ~r(Les jeux de données suivants sont soumis à une obligation de réutilisation en vertu de l'article 122 de la loi climat et résilience mais ne sont plus publiés avec une licence ouverte)
    )

    assert [
             %DB.Dataset{custom_tags: ["foo"], licence: "odc-odbl"},
             %DB.Dataset{custom_tags: ["foo", "loi-climat-resilience"], licence: "fr-lo"}
           ] = DB.Repo.reload!([dataset, lo_dataset])
  end

  test "does not send an email if there are no datasets to handle" do
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience"], licence: "fr-lo")
    assert :ok == perform_job(DatasetsClimateResilienceBillNotLOLicenceJob, %{})
    # No e-mails have been sent
  end
end
