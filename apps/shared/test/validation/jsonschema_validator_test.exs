defmodule Shared.Validation.JSONSchemaValidatorTest do
  use Shared.CacheCase
  import Shared.Validation.JSONSchemaValidator

  setup do
    old_value = Application.fetch_env!(:transport, :schemas_impl)
    on_exit(fn -> Application.put_env(:transport, :schemas_impl, old_value) end)
    Application.put_env(:transport, :schemas_impl, Transport.Shared.Schemas)
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

  describe "validate" do
    test "valid object" do
      assert %{"errors_count" => 0, "has_errors" => false, "errors" => []} ==
               validate(name_jsonschema(), %{"name" => "foo"})
    end

    test "invalid object" do
      assert %{"errors_count" => 1, "has_errors" => true, "errors" => ["#: Required property name was not present."]} ==
               validate(name_jsonschema(), %{})

      assert %{
               "errors_count" => 1,
               "has_errors" => true,
               "errors" => ["#/name: Type mismatch. Expected String but got Integer."]
             } ==
               validate(name_jsonschema(), %{"name" => 42})
    end

    test "with an url and a valid payload" do
      url = "http://example.com/file"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [], follow_redirect: true ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"name" => "foo"})}}
      end)

      assert %{"errors_count" => 0, "has_errors" => false, "errors" => []} == validate(name_jsonschema(), url)
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
  end

  defp name_jsonschema do
    %ExJsonSchema.Schema.Root{
      schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
      version: 7
    }
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
        schemas:
          - path: schema.json
        versions:
          - 0.1.0
      """

      %HTTPoison.Response{body: body, status_code: 200}
    end)
  end
end
