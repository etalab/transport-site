defmodule Transport.Jobs.ResourceHistoryJSONSchemaValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.ResourceHistoryJSONSchemaValidationJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can validate a single ResourceHistory" do
    %{id: resource_history_id} =
      insert(:resource_history, %{
        payload: %{
          "schema_name" => sample_json_schema_name = "sample_json_schema",
          "schema_version" => schema_version = "0.4.2",
          "permanent_url" => permanent_url = "https://example.com/permanent_url"
        }
      })

    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:load_jsonschema_for_schema, fn ^sample_json_schema_name, ^schema_version ->
      %ExJsonSchema.Schema.Root{
        schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
        version: 7
      }
    end)

    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:validate, fn _schema, ^permanent_url ->
      %{"has_errors" => false, "errors_count" => 0, "errors" => []}
    end)

    assert :ok == perform_job(ResourceHistoryJSONSchemaValidationJob, %{resource_history_id: resource_history_id})

    assert %{
             result: %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validation_performed" => true},
             resource_history_id: ^resource_history_id,
             command: nil,
             data_vis: nil,
             validation_timestamp: _,
             validator: "EXJSONSchema",
             validator_version: validator_version
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)

    assert "0." <> _ = validator_version
  end

  test "discards job if already validated" do
    rh = insert(:resource_history, %{payload: %{"schema_name" => Ecto.UUID.generate(), "schema_version" => "0.1.2"}})

    insert(:multi_validation, %{
      resource_history_id: rh.id,
      validator: Transport.Validators.EXJSONSchema.validator_name()
    })

    assert {:cancel, _} = perform_job(ResourceHistoryJSONSchemaValidationJob, %{resource_history_id: rh.id})
  end

  test "enqueues jobs for all ResourceHistory with a JSON Schema schema that have not been validated" do
    sample_json_schema_name = "sample_json_schema"
    # needs validation: no MultiValidation
    rh1 = insert(:resource_history, %{payload: %{"schema_name" => sample_json_schema_name}})
    # does not need validation: already validated with the JSON Schema validator
    rh2 = insert(:resource_history, %{payload: %{"schema_name" => sample_json_schema_name}})

    insert(:multi_validation, %{
      resource_history_id: rh2.id,
      validator: Transport.Validators.EXJSONSchema.validator_name()
    })

    # needs validation: validated with another validator
    rh3 = insert(:resource_history, %{payload: %{"schema_name" => sample_json_schema_name}})
    insert(:multi_validation, %{resource_history_id: rh3.id, validator: Ecto.UUID.generate()})
    # does not need validation: schema is not a JSON Schema
    _rh4 = insert(:resource_history, %{payload: %{"schema_name" => Ecto.UUID.generate()}})

    Transport.Shared.Schemas.Mock |> expect(:schemas_by_type, fn "jsonschema" -> %{sample_json_schema_name => %{}} end)

    assert :ok == perform_job(ResourceHistoryJSONSchemaValidationJob, %{})

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryJSONSchemaValidationJob,
      args: %{"resource_history_id" => rh1.id}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryJSONSchemaValidationJob,
      args: %{"resource_history_id" => rh3.id}
    )

    assert 2 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryJSONSchemaValidationJob))
  end
end
