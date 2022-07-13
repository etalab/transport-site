defmodule Shared.Validation.JSONSchemaValidatorTest do
  use Shared.CacheCase
  import Shared.Validation.JSONSchemaValidator

  setup do
    Mox.stub_with(Transport.Shared.Schemas.Mock, Transport.Shared.Schemas)
    :ok
  end

  describe "load_jsonschema_for_schema" do
    test "schema-zfe" do
      setup_schemas_response()
      setup_zfe_schema()
      schema = load_jsonschema_for_schema(schema_name = "etalab/schema-zfe")

      assert %ExJsonSchema.Schema.Root{
               schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
               version: 7
             } = schema

      assert_cache_key_has_ttl("jsonschema_#{schema_name}_latest")

      assert ExJsonSchema.Validator.valid?(schema, %{"name" => "foo"})
    end

    test "non existing schema" do
      setup_schemas_response()

      assert_raise RuntimeError, fn ->
        load_jsonschema_for_schema("etalab/foo")
      end
    end

    test "with a specific version" do
      schema_version = "0.7.1"
      setup_schemas_response()
      setup_zfe_schema(schema_version)
      schema = load_jsonschema_for_schema(schema_name = "etalab/schema-zfe", schema_version)

      assert %ExJsonSchema.Schema.Root{
               schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
               version: 7
             } = schema

      assert_cache_key_has_ttl("jsonschema_#{schema_name}_#{schema_version}")
    end
  end

  describe "validate" do
    test "valid object" do
      assert %{
               "errors_count" => 0,
               "has_errors" => false,
               "errors" => [],
               "validator" => Shared.Validation.JSONSchemaValidator
             } ==
               validate(name_jsonschema(), %{"name" => "foo"})
    end

    test "invalid object" do
      assert %{
               "errors_count" => 1,
               "has_errors" => true,
               "errors" => ["#: Required property name was not present."],
               "validator" => Shared.Validation.JSONSchemaValidator
             } ==
               validate(name_jsonschema(), %{})

      assert %{
               "errors_count" => 1,
               "has_errors" => true,
               "errors" => ["#/name: Type mismatch. Expected String but got Integer."],
               "validator" => Shared.Validation.JSONSchemaValidator
             } ==
               validate(name_jsonschema(), %{"name" => 42})
    end

    test "with an url and a valid payload" do
      url = "http://example.com/file"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [], follow_redirect: true ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"name" => "foo"})}}
      end)

      assert %{
               "errors_count" => 0,
               "has_errors" => false,
               "errors" => [],
               "validator" => Shared.Validation.JSONSchemaValidator
             } == validate(name_jsonschema(), url)
    end

    test "with an url and a server error" do
      url = "http://example.com/file"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [], follow_redirect: true ->
        {:ok, %HTTPoison.Response{status_code: 500, body: "error"}}
      end)

      assert nil == validate(name_jsonschema(), url)
    end

    test "with an url and an invalid payload" do
      url = "http://example.com/file"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [], follow_redirect: true ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "error"}}
      end)

      assert nil == validate(name_jsonschema(), url)
    end

    test "supports version up to 7" do
      base_schema = %{"type" => "object", "properties" => %{"foo" => %{"type" => "string"}}}
      v7_schema = Map.put(base_schema, "$schema", "http://json-schema.org/draft-07/schema")

      assert ExJsonSchema.Schema.resolve(v7_schema)

      # 2019-09 was previously known as version 8
      assert_raise ExJsonSchema.Schema.UnsupportedSchemaVersionError, fn ->
        base_schema
        |> Map.put("$schema", "https://json-schema.org/draft/2019-09/schema")
        |> ExJsonSchema.Schema.resolve()
      end
    end

    test "can validate dependencies" do
      schema = %ExJsonSchema.Schema.Root{
        schema: %{
          "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "integer"}},
          "type" => "object",
          "dependencies" => %{"name" => ["age"], "age" => ["name"]}
        },
        version: 7
      }

      assert %{
               "errors" => ["#: Property name depends on property age to be present but it was not."],
               "errors_count" => 1,
               "has_errors" => true,
               "validator" => Shared.Validation.JSONSchemaValidator
             } == validate(schema, %{"name" => "Bob"})

      assert %{
               "errors" => ["#: Property age depends on property name to be present but it was not."],
               "errors_count" => 1,
               "has_errors" => true,
               "validator" => Shared.Validation.JSONSchemaValidator
             } == validate(schema, %{"age" => 42})

      # Our Elixir validator does not recognise `dependentRequired` yet,
      # even if it exists in the JSONSchema spec
      # https://json-schema.org/understanding-json-schema/reference/conditionals.html#id4
      #
      # See https://github.com/etalab/transport-site/issues/2347
      {value, base_schema} = Map.pop!(schema.schema, "dependencies")

      dependent_required_schema = %ExJsonSchema.Schema.Root{
        schema: Map.put(base_schema, "dependentRequired", value),
        version: 7
      }

      assert Map.has_key?(dependent_required_schema.schema, "dependentRequired")

      assert %{"has_errors" => false} = validate(dependent_required_schema, %{"name" => "Bob"})
      assert %{"has_errors" => false} = validate(dependent_required_schema, %{"age" => 42})
    end
  end

  defp name_jsonschema do
    %ExJsonSchema.Schema.Root{
      schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
      version: 7
    }
  end

  defp setup_zfe_schema(version \\ "0.7.2") do
    url = "https://schema.data.gouv.fr/schemas/etalab/schema-zfe/#{version}/schema.json"

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
    url = "https://schema.data.gouv.fr/schemas.json"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      %HTTPoison.Response{body: File.read!("#{__DIR__}/../fixtures/schemas.json"), status_code: 200}
    end)
  end
end
