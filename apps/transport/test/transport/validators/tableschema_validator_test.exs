defmodule Transport.Validators.TableSchemaTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  alias Transport.Validators.TableSchema

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
          "schema_name" => schema_name = "etalab/schema-lieux-covoiturage",
          "schema_version" => schema_version = "0.4.2"
        }
      )

    expected_command_url = setup_mock_validator_url(schema_name, permanent_url, schema_version)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn ^schema_name, ^permanent_url, ^schema_version ->
      %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validata-api-version" => "0.13.37"}
    end)

    assert :ok == TableSchema.validate_and_save(resource_history)

    assert %{
             result: %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validation_performed" => true},
             resource_history_id: ^resource_history_id,
             command: ^expected_command_url,
             data_vis: nil,
             validation_timestamp: _,
             validator: "validata-api",
             validator_version: "0.13.37"
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)
  end

  test "when validator returns nil" do
    %{id: resource_history_id} =
      resource_history =
      insert(:resource_history,
        payload: %{
          "permanent_url" => permanent_url = "https://example.com/permanent",
          "schema_name" => schema_name = "etalab/schema-lieux-covoiturage",
          "schema_version" => schema_version = "0.4.2"
        }
      )

    expected_command_url = setup_mock_validator_url(schema_name, permanent_url, schema_version)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn ^schema_name, ^permanent_url, ^schema_version -> nil end)

    assert :ok == TableSchema.validate_and_save(resource_history)

    assert %{
             result: %{"validation_performed" => false},
             resource_history_id: ^resource_history_id,
             command: ^expected_command_url,
             data_vis: nil,
             validation_timestamp: _,
             validator: "validata-api",
             validator_version: nil
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)
  end

  def setup_mock_validator_url(schema_name, url, schema_version) do
    fake_url = "https://example.com/" <> Enum.join([schema_name, url, schema_version], "/")

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validator_api_url, fn ^schema_name, ^url, ^schema_version -> fake_url end)

    fake_url
  end
end
