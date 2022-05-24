defmodule Transport.Jobs.Backfill.ResourceHistoryValidationMetadataTest do
  use ExUnit.Case
  import Transport.Jobs.Backfill.ResourceHistoryValidationMetadata
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @expected_hash "230d8358dc8e8890b4c58deeb62912ee2f20357ae92a5cc861b98e68fe31acb5"

  setup :verify_on_exit!

  describe "update_resource_history" do
    test "with a TableSchema" do
      permanent_url = "https://example.com/file"
      initial_content_hash = Ecto.UUID.generate()
      schema_name = "etalab/schema-zfe"
      resource = insert(:resource, schema_name: schema_name)

      resource_history =
        insert(:resource_history,
          resource: resource,
          payload: %{
            "permanent_url" => permanent_url,
            "content_hash" => initial_content_hash,
            "resource_metadata" => %{"validation" => %{"foo" => 42}, "bar" => "baz"}
          }
        )

      Transport.Shared.Schemas.Mock
      |> expect(:schemas_by_type, fn "tableschema" -> %{resource.schema_name => %{"title" => "foo"}} end)

      Transport.HTTPoison.Mock
      |> expect(:get!, fn ^permanent_url ->
        %HTTPoison.Response{status_code: 200, body: "body"}
      end)

      validation_result = %{"errors_count" => 0, "has_errors" => false, "errors" => []}

      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn ^schema_name, ^permanent_url, nil -> validation_result end)

      update_resource_history(resource_history.id)

      %DB.ResourceHistory{payload: payload} = DB.Repo.reload!(resource_history)

      assert %{
               "content_hash" => @expected_hash,
               "backfill_source" => "Elixir.Transport.Jobs.Backfill.ResourceHistoryValidationMetadata",
               "permanent_url" => permanent_url,
               "resource_metadata" => %{
                 "bar" => "baz",
                 "validation" =>
                   Map.merge(validation_result, %{"content_hash" => @expected_hash, "schema_type" => "tableschema"})
               }
             } == payload
    end

    test "with a JSON Schema" do
      permanent_url = "https://example.com/file"
      initial_content_hash = Ecto.UUID.generate()
      schema_name = "etalab/schema-amenagements-cyclables"
      resource = insert(:resource, schema_name: schema_name)

      resource_history =
        insert(:resource_history,
          resource: resource,
          payload: %{
            "permanent_url" => permanent_url,
            "content_hash" => initial_content_hash,
            "resource_metadata" => %{"validation" => %{"foo" => 42}, "bar" => "baz"}
          }
        )

      Transport.Shared.Schemas.Mock
      |> expect(:schemas_by_type, fn "tableschema" -> %{} end)

      Transport.Shared.Schemas.Mock
      |> expect(:schemas_by_type, fn "jsonschema" -> %{resource.schema_name => %{"title" => "foo"}} end)

      Transport.HTTPoison.Mock
      |> expect(:get!, fn ^permanent_url ->
        %HTTPoison.Response{status_code: 200, body: "body"}
      end)

      validation_result = %{"errors_count" => 0, "has_errors" => false, "errors" => []}

      Shared.Validation.JSONSchemaValidator.Mock
      |> expect(:load_jsonschema_for_schema, fn ^schema_name ->
        %ExJsonSchema.Schema.Root{
          schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
          version: 7
        }
      end)

      Shared.Validation.JSONSchemaValidator.Mock
      |> expect(:validate, fn _schema, ^permanent_url ->
        validation_result
      end)

      update_resource_history(resource_history.id)

      %DB.ResourceHistory{payload: payload} = DB.Repo.reload!(resource_history)

      assert %{
               "content_hash" => @expected_hash,
               "backfill_source" => "Elixir.Transport.Jobs.Backfill.ResourceHistoryValidationMetadata",
               "permanent_url" => permanent_url,
               "resource_metadata" => %{
                 "bar" => "baz",
                 "validation" =>
                   Map.merge(validation_result, %{"content_hash" => @expected_hash, "schema_type" => "jsonschema"})
               }
             } == payload
    end
  end
end
