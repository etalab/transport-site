defmodule Transport.Validators.EXJSONSchemaTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  alias Transport.Validators.EXJSONSchema

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "inserts the expected data in the database" do
    %{id: resource_history_id} =
      resource_history =
      insert(:resource_history,
        payload: %{
          "permanent_url" => permanent_url = "https://example.com/permanent",
          "schema_name" => schema_name = "etalab/schema-zfe"
        }
      )

    mock_load_jsonschema(schema_name)

    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:validate, fn _schema, ^permanent_url ->
      %{"has_errors" => false, "errors_count" => 0, "errors" => []}
    end)

    assert :ok == EXJSONSchema.validate_and_save(resource_history)

    assert %{
             result: %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validation_performed" => true},
             resource_history_id: ^resource_history_id,
             command: nil,
             data_vis: nil,
             validation_timestamp: _,
             validator: "EXJSONSchema",
             validator_version: "0.9.1"
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)
  end

  test "perform_validation when validator returns nil" do
    schema_name = "etalab/schema-zfe"
    permanent_url = "https://example.com/permanent_url"

    mock_load_jsonschema(schema_name)

    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:validate, fn _schema, ^permanent_url -> nil end)

    assert %{"validation_performed" => false} == EXJSONSchema.perform_validation(schema_name, permanent_url)
  end

  defp mock_load_jsonschema(schema_name) do
    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:load_jsonschema_for_schema, fn ^schema_name ->
      %ExJsonSchema.Schema.Root{
        schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
        version: 7
      }
    end)
  end
end
