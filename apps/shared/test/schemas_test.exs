defmodule Transport.Shared.SchemasTest do
  use Shared.CacheCase
  import Transport.Shared.Schemas

  @base_url "https://schema.data.gouv.fr"

  setup do
    Mox.stub_with(Transport.Shared.Schemas.Mock, Transport.Shared.Schemas)
    :ok
  end

  test "transport_schemas" do
    assert ["etalab/schema-amenagements-cyclables", "etalab/schema-lieux-covoiturage", "etalab/schema-zfe"] ==
             Map.keys(transport_schemas())

    assert_cache_key_has_ttl("transport_schemas")
  end

  test "schemas_by_type" do
    assert ["etalab/schema-amenagements-cyclables", "etalab/schema-zfe"] == Map.keys(schemas_by_type("jsonschema"))
    assert ["etalab/schema-lieux-covoiturage"] == Map.keys(schemas_by_type("tableschema"))
  end

  test "read_latest_schema" do
    setup_schema_response("#{@base_url}/schemas/etalab/schema-zfe/0.7.2/schema.json")

    assert %{"foo" => "bar"} == read_latest_schema("etalab/schema-zfe")
    assert_cache_key_has_ttl("latest_schema_etalab/schema-zfe")

    setup_schema_response("#{@base_url}/schemas/etalab/schema-lieux-covoiturage/0.2.2/schema.json")

    assert %{"foo" => "bar"} == read_latest_schema("etalab/schema-lieux-covoiturage")
    assert_cache_key_has_ttl("latest_schema_etalab/schema-lieux-covoiturage")
  end

  describe "schema_url" do
    test "simple case" do
      assert "#{@base_url}/schemas/etalab/schema-zfe/latest/schema.json" ==
               schema_url("etalab/schema-zfe", "latest")

      assert "#{@base_url}/schemas/etalab/schema-zfe/0.7.2/schema.json" ==
               schema_url("etalab/schema-zfe", "0.7.2")
    end

    test "with a custom schema filename" do
      assert "#{@base_url}/schemas/etalab/schema-amenagements-cyclables/latest/schema_amenagements_cyclables.json" ==
               schema_url("etalab/schema-amenagements-cyclables", "latest")
    end

    test "makes sure schema and version are valid" do
      assert_raise KeyError, ~r(^key "foo" not found in), fn ->
        schema_url("foo", "latest")
      end

      assert_raise KeyError, "foo is not a valid version for etalab/schema-zfe", fn ->
        schema_url("etalab/schema-zfe", "foo")
      end
    end
  end

  defp assert_cache_key_has_ttl(cache_key, expected_ttl \\ 300) do
    assert_in_delta Cachex.ttl!(cache_name(), cache_key), :timer.seconds(expected_ttl), :timer.seconds(1)
  end

  defp setup_schema_response(expected_url) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^expected_url ->
      %HTTPoison.Response{body: ~s({"foo": "bar"}), status_code: 200}
    end)
  end

  defp setup_schemas_response do
    url = "https://schema.data.gouv.fr/schemas.yml"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      body = """
      foo/bar:
        email: nope@example.com
      etalab/schema-zfe:
        consolidation: null
        description: Spécification du schéma de données des Zones à Faibles Emissions
        email: contact@transport.beta.gouv.fr
        external_doc: https://doc.transport.data.gouv.fr/producteurs/zones-a-faibles-emissions
        external_tool: null
        has_changelog: true
        homepage: https://github.com/etalab/schema-zfe
        latest_version: 0.7.2
        schemas:
        - examples: []
          latest_url: https://schema.data.gouv.fr/schemas/etalab/schema-zfe/0.7.2/schema.json
          original_path: schema.json
          path: schema.json
          title: Zone à Faibles Emissions
          versions:
          - 0.6.1
          - 0.7.0
          - 0.7.1
          - 0.7.2
        title: Zone à Faibles Emissions
        type: jsonschema
        versions:
        - 0.6.1
        - 0.7.0
        - 0.7.1
        - 0.7.2
      etalab/schema-lieux-covoiturage:
        consolidation:
          dataset_id: 5d6eaffc8b4c417cdc452ac3
          tags:
          - covoiturage
        description: Spécification des lieux permettant le covoiturage
        email: contact@transport.beta.gouv.fr
        external_doc: null
        external_tool: null
        has_changelog: true
        homepage: https://github.com/etalab/schema-lieux-covoiturage
        latest_version: 0.2.2
        schemas:
        - examples:
          - name: exemple-valide
            path: https://github.com/etalab/schema-lieux-covoiturage/raw/v0.2.2/exemple-valide.csv
            title: Ressource valide
          - name: exemple-invalide
            path: https://github.com/etalab/schema-lieux-covoiturage/raw/v0.2.2/exemple-invalide.csv
            title: Ressource invalide
          latest_url: https://schema.data.gouv.fr/schemas/etalab/schema-lieux-covoiturage/0.2.2/schema.json
          original_path: schema.json
          path: schema.json
          title: Lieux de covoiturage
          versions:
          - 0.0.1
          - 0.1.0
          - 0.1.1
          - 0.1.2
          - 0.2.0
          - 0.2.1
          - 0.2.2
        title: Lieux de covoiturage
        type: tableschema
        versions:
        - 0.0.1
        - 0.1.0
        - 0.1.1
        - 0.1.2
        - 0.2.0
        - 0.2.1
        - 0.2.2
      etalab/schema-amenagements-cyclables:
        consolidation: null
        description: Spécification du schéma de données d'aménagements cyclables
        email: contact@transport.beta.gouv.fr
        external_doc: https://doc.transport.data.gouv.fr/producteurs/amenagements-cyclables
        external_tool: https://github.com/etalab/schema-amenagements-cyclables/tree/master/tools
        has_changelog: true
        homepage: https://github.com/etalab/schema_amenagements_cyclables
        latest_version: 0.3.3
        schemas:
        - examples: []
          latest_url: https://schema.data.gouv.fr/schemas/etalab/schema-amenagements-cyclables/0.3.3/schema_amenagements_cyclables.json
          original_path: schema_amenagements_cyclables.json
          path: schema_amenagements_cyclables.json
          title: Aménagements cyclables
          versions:
          - 0.1.0
          - 0.2.0
          - 0.2.1
          - 0.2.2
          - 0.2.3
          - 0.3.0
          - 0.3.1
          - 0.3.2
          - 0.3.3
        title: Aménagements cyclables
        type: jsonschema
        versions:
        - 0.1.0
        - 0.2.0
        - 0.2.1
        - 0.2.2
        - 0.2.3
        - 0.3.0
        - 0.3.1
        - 0.3.2
        - 0.3.3
      """

      %HTTPoison.Response{body: body, status_code: 200}
    end)
  end
end
