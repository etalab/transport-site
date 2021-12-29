defmodule Transport.Shared.SchemasTest do
  use ExUnit.Case, async: false
  import Shared.Application, only: [cache_name: 0]
  import Transport.Shared.Schemas
  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
  end

  test "transport_schemas" do
    setup_schemas_response()

    assert ["etalab/schema-lieux-covoiturage", "etalab/schema-zfe"] == Map.keys(transport_schemas())
    assert_cache_key_has_ttl("transport_schemas")
  end

  test "schemas_by_type" do
    setup_schemas_response()

    assert ["etalab/schema-zfe"] == Map.keys(schemas_by_type("jsonschema"))
    assert ["etalab/schema-lieux-covoiturage"] == Map.keys(schemas_by_type("tableschema"))
  end

  test "read_latest_schema" do
    setup_schemas_response()
    setup_schema_response("https://schema.data.gouv.fr/schemas/etalab/schema-zfe/0.7.2/schema.json")

    assert %{"foo" => "bar"} == read_latest_schema("etalab/schema-zfe")
    assert_cache_key_has_ttl("latest_schema_etalab/schema-zfe")

    setup_schema_response("https://schema.data.gouv.fr/schemas/etalab/schema-lieux-covoiturage/0.2.2/schema.json")

    assert %{"foo" => "bar"} == read_latest_schema("etalab/schema-lieux-covoiturage")
    assert_cache_key_has_ttl("latest_schema_etalab/schema-lieux-covoiturage")
  end

  defp assert_cache_key_has_ttl(cache_key, expected_ttl \\ 300) do
    assert_in_delta Cachex.ttl!(cache_name(), cache_key), :timer.seconds(expected_ttl), :timer.seconds(1)
  end

  defp setup_schema_response(expected_url) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^expected_url ->
      body = ~S"""
      {"foo": "bar"}
      """

      %HTTPoison.Response{body: body, status_code: 200}
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
      """

      %HTTPoison.Response{body: body, status_code: 200}
    end)
  end
end
