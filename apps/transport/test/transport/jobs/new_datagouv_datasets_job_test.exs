defmodule Transport.Test.Transport.Jobs.NewDatagouvDatasetsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Swoosh.TestAssertions
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
    thursday_at_noon = ~U[2022-10-27 12:00:00Z]
    friday_at_noon = ~U[2022-10-28 12:00:00Z]
    saturday_at_noon = ~U[2022-10-29 12:00:00Z]
    monday_night = ~U[2022-10-31 03:00:00Z]
    monday_at_noon = ~U[2022-10-31 12:00:00Z]
    tuesday_at_noon = ~U[2022-11-01 12:00:00Z]
    wednesday_night = ~U[2022-11-02 03:00:00Z]

    base = %{
      "title" => "",
      "resources" => [],
      "tags" => [],
      "description" => "",
      "internal" => %{"created_at_internal" => DateTime.to_string(tuesday_at_noon)},
      "id" => Ecto.UUID.generate()
    }

    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate(), is_active: true)

    created_on_thursday = %{
      base
      | "internal" => %{"created_at_internal" => DateTime.to_string(thursday_at_noon)},
        "title" => "GTFS de Dôle (jeudi)"
    }

    created_on_friday = %{
      base
      | "internal" => %{"created_at_internal" => DateTime.to_string(friday_at_noon)},
        "title" => "GTFS de Dôle (vendredi)"
    }

    created_on_friday_but_already_imported = %{
      created_on_friday
      | "tags" => ["gbfs"],
        "id" => datagouv_id
    }

    created_on_saturday = %{
      base
      | "internal" => %{"created_at_internal" => DateTime.to_string(saturday_at_noon)},
        "title" => "GTFS de Besançon (samedi)"
    }

    created_on_monday = %{
      base
      | "internal" => %{"created_at_internal" => DateTime.to_string(monday_at_noon)},
        "title" => "GTFS de Macon (lundi)"
    }

    created_on_tuesday = %{base | "title" => "GTFS de Dijon (mardi)"}

    created_on_tuesday_but_already_imported = %{
      created_on_tuesday
      | "tags" => ["gbfs"],
        "id" => datagouv_id
    }

    datasets = [
      created_on_thursday,
      created_on_friday,
      created_on_friday_but_already_imported,
      created_on_saturday,
      created_on_monday,
      base,
      created_on_tuesday,
      created_on_tuesday_but_already_imported
    ]

    assert [true, true, true, true, true, false, true, true] ==
             Enum.map(datasets, &NewDatagouvDatasetsJob.dataset_is_relevant?/1)

    assert [created_on_tuesday] == filtered_datasets_as_of(datasets, wednesday_night)

    assert [created_on_friday, created_on_saturday] ==
             filtered_datasets_as_of(datasets, monday_night)
  end

  defp filtered_datasets_as_of(datasets, %DateTime{} = then) do
    NewDatagouvDatasetsJob.filtered_datasets(as_of(datasets, then), then)
  end

  defp as_of(datasets, %DateTime{} = then) do
    Enum.reject(
      datasets,
      &NewDatagouvDatasetsJob.after_datetime?(get_in(&1, ["internal", "created_at_internal"]), then)
    )
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

    defp test_email_sending(%DateTime{} = inserted_at, expected_body) do
      dataset = %{
        "title" => "GTFS de Dijon",
        "resources" => [],
        "tags" => [],
        "description" => "",
        "internal" => %{
          "created_at_internal" => inserted_at |> DateTime.add(-23, :hour) |> DateTime.to_iso8601()
        },
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

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{}, inserted_at: inserted_at)

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{"", "deploiement@transport.data.gouv.fr"}],
                             subject: "Nouveaux jeux de données à référencer - data.gouv.fr",
                             text_body: nil,
                             html_body: body
                           } ->
        assert body =~ ~s(<a href="#{dataset["page"]}">#{dataset["title"]}</a>)
        assert body =~ expected_body
      end)
    end

    test "sends an email on monday" do
      monday_night = ~U[2022-10-31 03:00:00Z]

      test_email_sending(
        monday_night,
        ~s(Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières 72h)
      )
    end

    test "sends an email on other week day" do
      wednesday_night = ~U[2022-11-02 03:00:00Z]

      test_email_sending(
        wednesday_night,
        ~s(Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières 24h)
      )
    end
  end
end
