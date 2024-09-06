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
    Sentry.Test.start_collecting_sentry_reports()
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "dataset_is_relevant?" do
    base = %{"title" => "", "resources" => [], "tags" => [], "description" => ""}

    relevant_fn = fn dataset ->
      NewDatagouvDatasetsJob.rules()
      |> Enum.filter(&NewDatagouvDatasetsJob.dataset_is_relevant?(dataset, &1))
      |> case do
        [rule] -> rule
        _ -> :no_match
      end
    end

    assert %{category: "Transport en commun"} = relevant_fn.(%{base | "title" => "GTFS de Dijon"})
    assert %{category: "Transport en commun"} = relevant_fn.(%{base | "description" => "GTFS de Dijon"})
    assert %{category: "Transport en commun"} = relevant_fn.(%{base | "tags" => [Ecto.UUID.generate(), "gtfs"]})

    assert %{category: "Freefloating"} =
             relevant_fn.(%{
               base
               | "resources" => [%{"format" => "GBFS", "description" => ""}]
             })

    assert %{category: "Covoiturage et ZFE"} =
             relevant_fn.(%{
               base
               | "resources" => [
                   %{"format" => "csv", "schema" => %{"name" => "etalab/schema-zfe"}, "description" => ""}
                 ]
             })

    assert %{category: "Transport en commun"} =
             relevant_fn.(%{
               base
               | "resources" => [%{"format" => "csv", "description" => "Horaires des bus"}]
             })

    assert :no_match == relevant_fn.(%{base | "title" => "Résultat des élections"})

    assert %{category: "IRVE"} =
             relevant_fn.(%{
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

    assert %{category: "Transport en commun"} = relevant_fn.(bdtopo_args)

    assert :no_match == relevant_fn.(Map.merge(bdtopo_args, %{"organization" => %{"id" => "5a83f81fc751df6f8573eb8a"}}))
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
             Enum.map(datasets, &dataset_is_relevant_for_any_rule?/1)

    assert [created_on_tuesday] == matching_datasets_as_of(datasets, wednesday_night)

    assert [created_on_friday, created_on_saturday] ==
             matching_datasets_as_of(datasets, monday_night)
  end

  test "rule_explanation" do
    assert "<p>Règles utilisées pour identifier ces jeux de données :</p>\n<ul>\n  <li>Formats : netex</li>\n  <li>Schémas : <vide></li>\n  <li>Mots-clés/tags : cassis, kir</li>\n</ul>\n" ==
             NewDatagouvDatasetsJob.rule_explanation(%{
               schemas: MapSet.new([]),
               tags: MapSet.new(["kir", "cassis"]),
               formats: MapSet.new(["netex"])
             })
  end

  describe "perform" do
    test "check_rules when schemas exist" do
      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, fn ->
        NewDatagouvDatasetsJob.rules() |> Enum.flat_map(& &1.schemas) |> Map.new(fn schema -> {schema, true} end)
      end)

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{"check_rules" => true})
    end

    test "check_rules when a schema does not exist" do
      expect(Transport.Shared.Schemas.Mock, :transport_schemas, fn ->
        %{"404" => true}
      end)

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{"check_rules" => true})

      sentry_events = Sentry.Test.pop_sentry_reports()

      NewDatagouvDatasetsJob.rules()
      |> Enum.reject(&Enum.empty?(&1.schemas))
      |> Enum.zip(sentry_events)
      |> Enum.each(fn {%{category: category}, event} ->
        assert event.message.formatted =~ ~r|^Transport.Jobs.NewDatagouvDatasetsJob: `#{category}` has invalid schemas|
      end)
    end

    test "no datasets" do
      setup_datagouv_api_response([])

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{}, inserted_at: DateTime.utc_now())
    end

    test "sends an email on Monday" do
      monday_night = ~U[2022-10-31 03:00:00Z]

      test_email_sending(
        monday_night,
        ~s(Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières 72h)
      )
    end

    test "sends an email on other weekday" do
      wednesday_night = ~U[2022-11-02 03:00:00Z]

      test_email_sending(
        wednesday_night,
        ~s(Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières 24h)
      )
    end

    test "sends multiple emails" do
      inserted_at = DateTime.utc_now()

      base = %{
        "resources" => [],
        "tags" => [],
        "description" => "",
        "internal" => %{
          "created_at_internal" => inserted_at |> DateTime.add(-23, :hour) |> DateTime.to_iso8601()
        },
        "id" => Ecto.UUID.generate(),
        "title" => nil,
        "page" => nil
      }

      datasets = [
        %{base | "title" => "GTFS de Dijon", "page" => "https://example.com/gtfs"},
        %{base | "title" => "GBFS de Dijon", "page" => "https://example.com/gbfs"}
      ]

      setup_datagouv_api_response(datasets)

      assert :ok == perform_job(NewDatagouvDatasetsJob, %{}, inserted_at: inserted_at)

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{"", "contact@transport.data.gouv.fr"}],
                             subject: "Nouveaux jeux de données Freefloating à référencer - data.gouv.fr",
                             text_body: nil,
                             html_body: body
                           } ->
        assert body =~ ~s(<a href="https://example.com/gbfs">GBFS de Dijon</a>)
      end)

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{"", "contact@transport.data.gouv.fr"}],
                             subject: "Nouveaux jeux de données Transport en commun à référencer - data.gouv.fr",
                             text_body: nil,
                             html_body: body
                           } ->
        assert body =~ ~s(<a href="https://example.com/gtfs">GTFS de Dijon</a>)
      end)
    end
  end

  defp matching_datasets_as_of(datasets, %DateTime{} = then) do
    as_of(datasets, then)
    |> NewDatagouvDatasetsJob.filtered_datasets(then)
    |> Enum.filter(&dataset_is_relevant_for_any_rule?/1)
  end

  defp dataset_is_relevant_for_any_rule?(dataset) do
    Enum.any?(NewDatagouvDatasetsJob.rules(), &NewDatagouvDatasetsJob.dataset_is_relevant?(dataset, &1))
  end

  defp as_of(datasets, %DateTime{} = then) do
    Enum.reject(
      datasets,
      &NewDatagouvDatasetsJob.after_datetime?(get_in(&1, ["internal", "created_at_internal"]), then)
    )
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

    assert dataset_is_relevant_for_any_rule?(dataset)

    setup_datagouv_api_response([dataset])

    assert :ok == perform_job(NewDatagouvDatasetsJob, %{}, inserted_at: inserted_at)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{"", "contact@transport.data.gouv.fr"}],
                           subject: "Nouveaux jeux de données Transport en commun à référencer - data.gouv.fr",
                           text_body: nil,
                           html_body: body
                         } ->
      assert body =~ ~s(<a href="#{dataset["page"]}">#{dataset["title"]}</a>)
      assert body =~ expected_body
    end)
  end

  defp setup_datagouv_api_response(data) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/?sort=-created&page_size=500",
                        [],
                        [timeout: 30_000, recv_timeout: 30_000] ->
      %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"data" => data})}
    end)
  end
end
