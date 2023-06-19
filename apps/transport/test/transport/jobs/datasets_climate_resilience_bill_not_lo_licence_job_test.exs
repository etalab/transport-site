defmodule Transport.Test.Transport.Jobs.DatasetsClimateResilienceBillNotLOLicenceJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.DatasetsClimateResilienceBillNotLOLicenceJob

  setup :verify_on_exit!

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

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "deploiement@transport.beta.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "Jeux de données article 122 avec licence inappropriée",
                             "",
                             html_content ->
      assert html_content =~ ~s(<a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html_content =~
               ~s(Les jeux de données suivants sont soumis à une obligation de réutilisation en vertu de l'article 122 de la loi climat et résilience mais ne sont plus publiés avec une licence ouverte)

      :ok
    end)

    assert :ok == perform_job(DatasetsClimateResilienceBillNotLOLicenceJob, %{})

    assert [
             %DB.Dataset{custom_tags: ["foo"], licence: "odc-odbl"},
             %DB.Dataset{custom_tags: ["foo", "loi-climat-resilience"], licence: "fr-lo"}
           ] = DB.Repo.reload!([dataset, lo_dataset])
  end
end
