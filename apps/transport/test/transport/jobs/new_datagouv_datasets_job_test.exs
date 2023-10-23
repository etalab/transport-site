defmodule Transport.Test.Transport.Jobs.NewDatagouvDatasetsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.NewDatagouvDatasetsJob

  setup :verify_on_exit!

  doctest NewDatagouvDatasetsJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "dataset_is_relevant?" do
    base = %{"title" => "", "resources" => [], "tags" => [], "description" => ""}
    assert NewDatagouvDatasetsJob.dataset_is_relevant?(%{base | "title" => "GTFS de Dijon"})
    assert NewDatagouvDatasetsJob.dataset_is_relevant?(%{base | "description" => "GTFS de Dijon"})
    assert NewDatagouvDatasetsJob.dataset_is_relevant?(%{base | "tags" => [Ecto.UUID.generate(), "gtfs"]})

    assert NewDatagouvDatasetsJob.dataset_is_relevant?(%{
             base
             | "resources" => [%{"format" => "GBFS", "description" => ""}]
           })

    Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{"etalab/foo" => %{}} end)

    assert NewDatagouvDatasetsJob.dataset_is_relevant?(%{
             base
             | "resources" => [%{"format" => "csv", "schema" => %{"name" => "etalab/foo"}, "description" => ""}]
           })

    assert NewDatagouvDatasetsJob.dataset_is_relevant?(%{
             base
             | "resources" => [%{"format" => "csv", "description" => "Horaires des bus"}]
           })

    refute NewDatagouvDatasetsJob.dataset_is_relevant?(%{base | "title" => "Résultat des élections"})

    refute NewDatagouvDatasetsJob.dataset_is_relevant?(%{
             base
             | "resources" => [
                 %{"format" => "csv", "schema" => %{"name" => "etalab/schema-irve-statique"}, "description" => ""}
               ]
           })

    # Uses `ignore_dataset?/1` to ignore specific datasets
    bdtopo_args =
      Map.merge(base, %{
        "title" => "BDTOPO© - Chefs-Lieux pour le département de l'Eure-et-Loir",
        "tags" => ["transport"]
      })

    assert NewDatagouvDatasetsJob.dataset_is_relevant?(bdtopo_args)

    refute NewDatagouvDatasetsJob.dataset_is_relevant?(
             Map.merge(bdtopo_args, %{"organization" => %{"id" => "5a83f81fc751df6f8573eb8a"}})
           )
  end

  test "filtered_datasets" do
    base = %{
      "title" => "",
      "resources" => [],
      "tags" => [],
      "description" => "",
      "created_at" => "2022-11-01 00:01:00+00:00",
      "id" => Ecto.UUID.generate()
    }

    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate(), is_active: true)

    datasets = [
      base,
      %{base | "created_at" => "2022-10-30 00:00:00+00:00", "title" => "GTFS de Dijon"},
      dataset_to_keep = %{base | "title" => "GTFS de Dijon"},
      %{base | "tags" => ["gbfs"], "id" => datagouv_id}
    ]

    assert [false, true, true, true] == Enum.map(datasets, &NewDatagouvDatasetsJob.dataset_is_relevant?/1)

    assert [true, false, true, true] ==
             Enum.map(datasets, &NewDatagouvDatasetsJob.after_datetime?(&1["created_at"], ~U[2022-11-01 00:00:00Z]))

    assert [dataset_to_keep] == NewDatagouvDatasetsJob.filtered_datasets(datasets, ~U[2022-11-02 00:00:00Z])
  end

  describe "perform" do
    test "no datasets" do
      Transport.HTTPoison.Mock
      |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/?sort=-created&page_size=500",
                          [],
                          [timeout: 30_000, recv_timeout: 30_000] ->
        %HTTPoison.Response{status_code: 200, body: ~s({"data":[]})}
      end)

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{}, inserted_at: DateTime.utc_now())
    end

    test "sends an email" do
      dataset = %{
        "title" => "GTFS de Dijon",
        "resources" => [],
        "tags" => [],
        "description" => "",
        "created_at" => DateTime.utc_now() |> DateTime.add(-23, :hour) |> DateTime.to_iso8601(),
        "page" => "https://example.com/link",
        "id" => Ecto.UUID.generate()
      }

      assert NewDatagouvDatasetsJob.dataset_is_relevant?(dataset)

      Transport.HTTPoison.Mock
      |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/?sort=-created&page_size=500",
                          [],
                          [timeout: 30_000, recv_timeout: 30_000] ->
        %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"data" => [dataset]})}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name,
                               "contact@transport.data.gouv.fr" = _from_email,
                               "deploiement@transport.data.gouv.fr" = _to_email,
                               _reply_to,
                               "Nouveaux jeux de données à référencer - data.gouv.fr" = _subject,
                               body,
                               _html_body ->
        assert body =~ ~s(* #{dataset["title"]} - #{dataset["page"]})
      end)

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{}, inserted_at: DateTime.utc_now())
    end
  end
end
