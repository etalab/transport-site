defmodule Transport.Test.Transport.Jobs.ConsolidateLEZsJob do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  alias Transport.Jobs.ConsolidateLEZsJob

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "resource type" do
    dataset = insert(:dataset, type: "low-emission-zones")
    zfe_aire = insert(:resource, datagouv_id: "foo", dataset: dataset, url: "https://example.com/aires.geojson")

    zfe_voies =
      insert(:resource,
        datagouv_id: "foo",
        dataset: dataset,
        url: "https://example.com/zfe_voies_speciale_ville.geojson"
      )

    assert ConsolidateLEZsJob.type(zfe_aire) == "aires"
    refute ConsolidateLEZsJob.is_voie?(zfe_aire)

    assert ConsolidateLEZsJob.type(zfe_voies) == "voies"
    assert ConsolidateLEZsJob.is_voie?(zfe_voies)
  end

  test "relevant_resources" do
    dataset = insert(:dataset, type: "low-emission-zones", organization: "Sample")

    pan_dataset =
      insert(:dataset, type: "low-emission-zones", organization: "Point d'Accès National transport.data.gouv.fr")

    zfe_aire =
      insert(:resource,
        datagouv_id: Ecto.UUID.generate(),
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    zfe_voies =
      insert(:resource,
        datagouv_id: Ecto.UUID.generate(),
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    _zfe_pan =
      insert(:resource,
        datagouv_id: Ecto.UUID.generate(),
        dataset: pan_dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    _zfe_aire_errors =
      insert(:resource,
        datagouv_id: Ecto.UUID.generate(),
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => true}}
      )

    assert [zfe_aire.id, zfe_voies.id] == ConsolidateLEZsJob.relevant_resources() |> Enum.map(& &1.id)
  end

  test "consolidate_features" do
    dataset = insert(:dataset, type: "low-emission-zones", organization: "Sample")

    zfe_aire =
      insert(:resource,
        datagouv_id: Ecto.UUID.generate(),
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    zfe_voies =
      insert(:resource,
        datagouv_id: Ecto.UUID.generate(),
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    insert(:resource_history,
      datagouv_id: zfe_aire.datagouv_id,
      payload: %{
        "permanent_url" => permanent_url_aires = "https://example.com/permanent_url/aires",
        "resource_metadata" => %{"validation" => %{"has_errors" => false}}
      }
    )

    insert(:resource_history,
      datagouv_id: zfe_voies.datagouv_id,
      payload: %{
        "permanent_url" => permanent_url_voies = "https://example.com/permanent_url/voies",
        "resource_metadata" => %{"validation" => %{"has_errors" => false}}
      }
    )

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^permanent_url_aires, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [["foo", "bar"]]})}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^permanent_url_voies, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [["bar", "baz"]]})}
    end)

    assert %{features: [["foo", "bar"], ["bar", "baz"]], type: "FeatureCollection"} ==
             ConsolidateLEZsJob.consolidate_features([zfe_aire, zfe_voies])
  end
end
