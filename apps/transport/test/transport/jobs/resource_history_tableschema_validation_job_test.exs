defmodule Transport.Jobs.ResourceHistoryTableSchemaValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.ResourceHistoryTableSchemaValidationJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can validate a single ResourceHistory" do
    fake_validator_url = "https://example.com/fake_validator_url"
    validata_api_version = "1.2.3"

    %{id: resource_history_id} =
      insert(:resource_history, %{
        payload: %{
          "schema_name" => schema_name = "sample_tableschema",
          "schema_version" => schema_version = "0.4.2",
          "permanent_url" => permanent_url = "https://example.com/permanent_url"
        }
      })

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn ^schema_name, ^permanent_url, ^schema_version ->
      %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validata-api-version" => validata_api_version}
    end)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validator_api_url, fn ^schema_name, ^permanent_url, ^schema_version ->
      fake_validator_url
    end)

    assert :ok == perform_job(ResourceHistoryTableSchemaValidationJob, %{resource_history_id: resource_history_id})

    assert %{
             result: %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validation_performed" => true},
             resource_history_id: ^resource_history_id,
             command: ^fake_validator_url,
             data_vis: nil,
             validation_timestamp: _,
             validator: "validata-api",
             validator_version: ^validata_api_version
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)
  end

  test "discards job if already validated" do
    rh = insert(:resource_history, %{payload: %{"schema_name" => Ecto.UUID.generate()}})

    insert(:multi_validation, %{
      resource_history_id: rh.id,
      validator: Transport.Validators.TableSchema.validator_name()
    })

    assert {:discard, _} = perform_job(ResourceHistoryTableSchemaValidationJob, %{resource_history_id: rh.id})
  end

  test "enqueues jobs for all ResourceHistory with a Table Schema schema that have not been validated" do
    schema_name = "sample_tableschema"
    # needs validation: no MultiValidation
    rh1 = insert(:resource_history, %{payload: %{"schema_name" => schema_name}})
    # does not need validation: already validated with the Table Schema validator
    rh2 = insert(:resource_history, %{payload: %{"schema_name" => schema_name}})

    insert(:multi_validation, %{
      resource_history_id: rh2.id,
      validator: Transport.Validators.TableSchema.validator_name()
    })

    # needs validation: validated with another validator
    rh3 = insert(:resource_history, %{payload: %{"schema_name" => schema_name}})
    insert(:multi_validation, %{resource_history_id: rh3.id, validator: Ecto.UUID.generate()})
    # does not need validation: schema is not a Table Schema
    _rh4 = insert(:resource_history, %{payload: %{"schema_name" => Ecto.UUID.generate()}})

    Transport.Shared.Schemas.Mock |> expect(:schemas_by_type, fn "tableschema" -> %{schema_name => %{}} end)

    assert :ok == perform_job(ResourceHistoryTableSchemaValidationJob, %{})

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryTableSchemaValidationJob,
      args: %{"resource_history_id" => rh1.id}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryTableSchemaValidationJob,
      args: %{"resource_history_id" => rh3.id}
    )

    assert 2 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryTableSchemaValidationJob))
  end
end
