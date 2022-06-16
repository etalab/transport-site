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
    zfe_aire = insert(:resource, dataset: dataset, url: "https://example.com/aires.geojson")

    zfe_voies =
      insert(:resource,
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
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    zfe_voies =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    _zfe_pan =
      insert(:resource,
        dataset: pan_dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    _zfe_aire_errors =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => true}}
      )

    assert [zfe_aire.id, zfe_voies.id] == ConsolidateLEZsJob.relevant_resources() |> Enum.map(& &1.id)
  end

  test "consolidate_features and consolidate" do
    dataset = insert(:dataset, type: "low-emission-zones", organization: "Sample")

    zfe_aire =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/aires.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    zfe_voies =
      insert(:resource,
        dataset: dataset,
        url: "https://example.com/voies.geojson",
        schema_name: "etalab/schema-zfe",
        metadata: %{"validation" => %{"has_errors" => false}}
      )

    insert(:resource_history,
      resource_id: zfe_aire.id,
      payload: %{
        "permanent_url" => permanent_url_aires = "https://example.com/permanent_url/aires",
        "resource_metadata" => %{"validation" => %{"has_errors" => false}}
      }
    )

    insert(:resource_history,
      resource_id: zfe_voies.id,
      payload: %{
        "permanent_url" => permanent_url_voies = "https://example.com/permanent_url/voies",
        "resource_metadata" => %{"validation" => %{"has_errors" => false}}
      }
    )

    setup_http_mocks(permanent_url_aires, permanent_url_voies)

    assert %{features: [["foo", "bar"], ["bar", "baz"]], type: "FeatureCollection"} ==
             ConsolidateLEZsJob.consolidate_features([zfe_aire, zfe_voies])

    setup_http_mocks(permanent_url_aires, permanent_url_voies)

    assert [
             {"aires", %{features: [["foo", "bar"]], type: "FeatureCollection"}},
             {"voies", %{features: [["bar", "baz"]], type: "FeatureCollection"}}
           ] == ConsolidateLEZsJob.consolidate()
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
               "https://demo.data.gouv.fr/api/1/datasets/624ff4b1bbb449a550264040/resources/3ddd29ee-00dd-40af-bc98-3367adbd0289/upload/"

      assert headers == [{"content-type", "multipart/form-data"}, {"X-API-KEY", nil}]
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :post, url, args, headers, [follow_redirect: true] ->
      {:multipart, [{:file, path, {"form-data", [name: "file", filename: "voies.geojson"]}, []}]} = args
      assert String.ends_with?(path, "voies.geojson")

      assert url ==
               "https://demo.data.gouv.fr/api/1/datasets/624ff4b1bbb449a550264040/resources/98c6bcdb-1205-4481-8859-f885290763f2/upload/"

      assert headers == [{"content-type", "multipart/form-data"}, {"X-API-KEY", nil}]
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)

    ConsolidateLEZsJob.update_files(data)

    refute File.exists?(ConsolidateLEZsJob.tmp_filepath("voies.geojson"))
    refute File.exists?(ConsolidateLEZsJob.tmp_filepath("aires.geojson"))
  end

  defp setup_http_mocks(url_aires, url_voies) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url_aires, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [["foo", "bar"]]})}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url_voies, [], follow_redirect: true ->
      %HTTPoison.Response{status_code: 200, body: ~s({"features": [["bar", "baz"]]})}
    end)
  end
end
