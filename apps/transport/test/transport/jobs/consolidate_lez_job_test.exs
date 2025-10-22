defmodule Transport.Test.Transport.Jobs.ConsolidateLEZsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.ConsolidateLEZsJob

  doctest Transport.Jobs.ConsolidateLEZsJob, import: true

  setup :verify_on_exit!

  setup do
    # Using the real implementation for the moment, then it falls back on `HTTPoison.Mock`
    Mox.stub_with(Datagouvfr.Client.Resources.Mock, Datagouvfr.Client.Resources.External)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "resource type" do
    dataset = insert(:dataset, type: "road-data")
    zfe_aire = insert(:resource, dataset: dataset, url: "https://example.com/aires.geojson")

    zfe_voies =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/zfe_voies_speciale_ville.geojson"
      )

    assert ConsolidateLEZsJob.type(zfe_aire) == "aires"
    refute ConsolidateLEZsJob.voie?(zfe_aire)

    assert ConsolidateLEZsJob.type(zfe_voies) == "voies"
    assert ConsolidateLEZsJob.voie?(zfe_voies)
  end

  test "relevant_resources" do
    dataset = insert(:dataset, type: "road-data", organization: "Sample")

    pan_dataset =
      insert(:dataset,
        type: "road-data",
        organization: "Point d'Accès National transport.data.gouv.fr",
        organization_id: "5abca8d588ee386ee6ece479"
      )

    zfe_aire =
      insert(:resource, dataset: dataset, url: "https://example.com/aires.geojson", schema_name: "etalab/schema-zfe")

    zfe_voies =
      insert(:resource, dataset: dataset, url: "https://example.com/voies.geojson", schema_name: "etalab/schema-zfe")

    _zfe_pan =
      insert(:resource,
        dataset: pan_dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe"
      )

    assert [zfe_aire.id, zfe_voies.id] == ConsolidateLEZsJob.relevant_resources() |> Enum.map(& &1.id)
  end

  test "consolidate_features and consolidate" do
    aom = insert(:aom, siren: "253800825", nom: "SMM de l’Aire Grenobloise", forme_juridique: "Métropole")
    dataset = insert(:dataset, type: "road-data", organization: "Sample", legal_owners_aom: [aom])

    zfe_aire =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe"
      )

    zfe_voies =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe"
      )

    # Should be ignored as this is not the most recent ResourceHistory / MultiValidation
    old_resource_history_aire =
      insert(:resource_history,
        resource_id: zfe_aire.id,
        payload: %{
          "permanent_url" => "https://example.com/permanent_url/aires##{Ecto.UUID.generate()}"
        }
      )

    resource_history_aire =
      insert(:resource_history,
        resource_id: zfe_aire.id,
        payload: %{
          "permanent_url" => permanent_url_aires = "https://example.com/permanent_url/aires"
        }
      )

    # Should be ignored as we will create an invalid MultiValidation linked to it
    resource_history_aire_invalid =
      insert(:resource_history,
        resource_id: zfe_aire.id,
        payload: %{
          "permanent_url" => "#{permanent_url_aires}##{Ecto.UUID.generate()}"
        }
      )

    resource_history_voies =
      insert(:resource_history,
        resource_id: zfe_voies.id,
        payload: %{
          "permanent_url" => permanent_url_voies = "https://example.com/permanent_url/voies"
        }
      )

    insert(:multi_validation, resource_history_id: old_resource_history_aire.id, result: %{"has_errors" => false})
    insert(:multi_validation, resource_history_id: resource_history_aire.id, result: %{"has_errors" => false})
    insert(:multi_validation, resource_history_id: resource_history_aire_invalid.id, result: %{"has_errors" => true})
    insert(:multi_validation, resource_history_id: resource_history_voies.id, result: %{"has_errors" => false})

    setup_http_mocks(permanent_url_aires, permanent_url_voies)

    assert %{
             features: [
               %{
                 "properties" => %{"foo" => "bar"},
                 "publisher" => %{
                   "forme_juridique" => "Métropole",
                   "nom" => "SMM de l’Aire Grenobloise",
                   "siren" => "253800825",
                   "zfe_id" => "GRENOBLE"
                 }
               },
               %{
                 "properties" => %{"bar" => "baz"},
                 "publisher" => %{
                   "forme_juridique" => "Métropole",
                   "nom" => "SMM de l’Aire Grenobloise",
                   "siren" => "253800825",
                   "zfe_id" => "GRENOBLE"
                 }
               }
             ],
             type: "FeatureCollection"
           } ==
             ConsolidateLEZsJob.consolidate_features([zfe_aire, zfe_voies])

    setup_http_mocks(permanent_url_aires, permanent_url_voies)

    assert [
             {
               "aires",
               %{
                 features: [
                   %{
                     "properties" => %{"foo" => "bar"},
                     "publisher" => %{
                       "forme_juridique" => "Métropole",
                       "nom" => "SMM de l’Aire Grenobloise",
                       "siren" => "253800825",
                       "zfe_id" => "GRENOBLE"
                     }
                   }
                 ],
                 type: "FeatureCollection"
               }
             },
             {
               "voies",
               %{
                 features: [
                   %{
                     "properties" => %{"bar" => "baz"},
                     "publisher" => %{
                       "forme_juridique" => "Métropole",
                       "nom" => "SMM de l’Aire Grenobloise",
                       "siren" => "253800825",
                       "zfe_id" => "GRENOBLE"
                     }
                   }
                 ],
                 type: "FeatureCollection"
               }
             }
           ] == ConsolidateLEZsJob.consolidate()
  end

  test "consolidate_features ignores resources without a valid resource history" do
    aom = insert(:aom, siren: "253800825", nom: "SMM de l’Aire Grenobloise", forme_juridique: "Métropole")
    dataset = insert(:dataset, type: "road-data", organization: "Sample", legal_owners_aom: [aom])

    zfe_aire =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe"
      )

    zfe_voies =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe"
      )

    resource_history_aire =
      insert(:resource_history,
        resource_id: zfe_aire.id,
        payload: %{
          "permanent_url" => permanent_url_aires = "https://example.com/permanent_url/aires"
        }
      )

    # Should be ignored as we will create an invalid MultiValidation linked to it
    resource_history_voies =
      insert(:resource_history,
        resource_id: zfe_voies.id,
        payload: %{
          "permanent_url" => "https://example.com/permanent_url/voies"
        }
      )

    insert(:multi_validation, resource_history_id: resource_history_aire.id, result: %{"has_errors" => false})
    insert(:multi_validation, resource_history_id: resource_history_voies.id, result: %{"has_errors" => true})

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^permanent_url_aires, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [{"properties": {"foo": "bar"}}]})}
    end)

    assert %{
             features: [
               %{
                 "properties" => %{"foo" => "bar"},
                 "publisher" => %{
                   "forme_juridique" => "Métropole",
                   "nom" => "SMM de l’Aire Grenobloise",
                   "siren" => "253800825",
                   "zfe_id" => "GRENOBLE"
                 }
               }
             ],
             type: "FeatureCollection"
           } ==
             ConsolidateLEZsJob.consolidate_features([zfe_aire, zfe_voies])
  end

  describe "publisher_details" do
    test "with an AOM" do
      aom = insert(:aom, siren: "253800825", nom: "SMM de l’Aire Grenobloise", forme_juridique: "Métropole")
      dataset = insert(:dataset, type: "road-data", organization: "Sample", legal_owners_aom: [aom])

      zfe_aire =
        insert(:resource,
          datagouv_id: Ecto.UUID.generate(),
          dataset: dataset,
          url: "https://example.com/aires.geojson",
          schema_name: "etalab/schema-zfe"
        )

      assert %{
               "forme_juridique" => "Métropole",
               "nom" => "SMM de l’Aire Grenobloise",
               "siren" => "253800825",
               "zfe_id" => "GRENOBLE"
             } == ConsolidateLEZsJob.publisher_details(zfe_aire)
    end

    test "without an AOM" do
      dataset = insert(:dataset, type: "road-data", organization: "Ville de Paris")

      zfe_aire =
        insert(:resource,
          datagouv_id: Ecto.UUID.generate(),
          dataset: dataset,
          url: "https://example.com/aires.geojson",
          schema_name: "etalab/schema-zfe"
        )

      assert %{
               "forme_juridique" => "Autre collectivité territoriale",
               "nom" => "Ville de Paris",
               "siren" => "217500016",
               "zfe_id" => "PARIS"
             } == ConsolidateLEZsJob.publisher_details(zfe_aire)
    end

    test "using autres_siren" do
      dataset = insert(:dataset, type: "road-data", organization: "Toulouse métropole")

      zfe_aire =
        insert(:resource,
          datagouv_id: Ecto.UUID.generate(),
          dataset: dataset,
          url: "https://example.com/aires.geojson",
          schema_name: "etalab/schema-zfe"
        )

      assert %{
               "forme_juridique" => "Métropole",
               "nom" => "Toulouse Métropole",
               "siren" => "243100518",
               "zfe_id" => "TOULOUSE"
             } == ConsolidateLEZsJob.publisher_details(zfe_aire)
    end
  end

  test "update_files" do
    data = [
      {"aires", %{features: [["foo", "bar"]], type: "FeatureCollection"}},
      {"voies", %{features: [["bar", "baz"]], type: "FeatureCollection"}}
    ]

    Transport.HTTPoison.Mock
    |> expect(:request, fn :post, url, args, headers, [follow_redirect: true] ->
      {:multipart, [{:file, path, {"form-data", [name: "file", filename: "aires.geojson"]}, []}]} = args
      assert String.ends_with?(path, "aires.geojson")

      assert url ==
               "https://demo.data.gouv.fr/api/1/datasets/zfe_fake_dataset_id/resources/zfe_aires_fake_resource_id/upload/"

      assert headers == [{"content-type", "multipart/form-data"}, {"X-API-KEY", "fake-datagouv-api-key"}]
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :post, url, args, headers, [follow_redirect: true] ->
      {:multipart, [{:file, path, {"form-data", [name: "file", filename: "voies.geojson"]}, []}]} = args
      assert String.ends_with?(path, "voies.geojson")

      assert url ==
               "https://demo.data.gouv.fr/api/1/datasets/zfe_fake_dataset_id/resources/zfe_voies_fake_resource_id/upload/"

      assert headers == [{"content-type", "multipart/form-data"}, {"X-API-KEY", "fake-datagouv-api-key"}]
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)

    ConsolidateLEZsJob.update_files(data)

    refute File.exists?(ConsolidateLEZsJob.tmp_filepath("voies.geojson"))
    refute File.exists?(ConsolidateLEZsJob.tmp_filepath("aires.geojson"))
  end

  test "perform" do
    aom = insert(:aom, siren: "253800825")
    dataset = insert(:dataset, type: "road-data", legal_owners_aom: [aom])

    zfe_aire =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe"
      )

    zfe_voies =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe"
      )

    resource_history_aire =
      insert(:resource_history,
        resource_id: zfe_aire.id,
        payload: %{
          "permanent_url" => permanent_url_aires = "https://example.com/permanent_url/aires"
        }
      )

    resource_history_voies =
      insert(:resource_history,
        resource_id: zfe_voies.id,
        payload: %{
          "permanent_url" => permanent_url_voies = "https://example.com/permanent_url/voies"
        }
      )

    insert(:multi_validation, resource_history_id: resource_history_aire.id, result: %{"has_errors" => false})
    insert(:multi_validation, resource_history_id: resource_history_voies.id, result: %{"has_errors" => false})

    setup_http_mocks(permanent_url_aires, permanent_url_voies)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :post, _url, args, _headers, [follow_redirect: true] ->
      {:multipart, [{:file, path, {"form-data", [name: "file", filename: "aires.geojson"]}, []}]} = args
      assert String.ends_with?(path, "aires.geojson")
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :post, _url, args, _headers, [follow_redirect: true] ->
      {:multipart, [{:file, path, {"form-data", [name: "file", filename: "voies.geojson"]}, []}]} = args
      assert String.ends_with?(path, "voies.geojson")
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)

    assert :ok == perform_job(ConsolidateLEZsJob, %{})

    # When Oban 2.19.0 will be released we should be able to make sure that
    # a broadcast notification was sent on the `:gossip` channel.
    # => We need to control the `job_id` when dispatching a job.
    # https://github.com/oban-bg/oban/commit/fae376232ef44d8405940d3d287ab8fd93912d0a
  end

  defp setup_http_mocks(url_aires, url_voies) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url_aires, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [{"properties": {"foo": "bar"}}]})}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url_voies, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [{"properties": {"bar": "baz"}}]})}
    end)
  end
end
