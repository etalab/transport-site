defmodule Shared.Validation.JSONSchemaValidatorTest do
  use ExUnit.Case, async: false
  import Shared.Application, only: [cache_name: 0]
  import Shared.Validation.JSONSchemaValidator
  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
  end

  describe "load_jsonschema_for_schema" do
    test "schema-zfe" do
      setup_schemas_response()
      setup_zfe_schema()
      schema = load_jsonschema_for_schema("etalab/schema-zfe")

      assert %ExJsonSchema.Schema.Root{
               schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
               version: 7
             } = schema

      assert ExJsonSchema.Validator.valid?(schema, %{"name" => "foo"})
    end

    test "non existing schema" do
      setup_schemas_response()

      assert_raise RuntimeError, fn ->
        load_jsonschema_for_schema("etalab/foo")
      end
    end
  end

  defp setup_zfe_schema do
    url = "https://schema.data.gouv.fr/schemas/etalab/schema-zfe/0.1.0/schema.json"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      body = """
      {
         "type": "object",
         "properties": {
            "name": {"type": "string"}
         },
         "required":["name"]
      }
      """

      %HTTPoison.Response{body: body, status_code: 200}
    end)
  end

  defp setup_schemas_response do
    url = "https://schema.data.gouv.fr/schemas.yml"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      body = """
      etalab/foo:
        email: contact@transport.beta.gouv.fr
        type: tableschema
      etalab/schema-zfe:
        email: contact@transport.beta.gouv.fr
        type: jsonschema
        latest_version: 0.1.0
      """

      %HTTPoison.Response{body: body, status_code: 200}
    end)
  end
end
