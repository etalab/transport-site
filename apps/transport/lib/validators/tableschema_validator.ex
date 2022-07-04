defmodule Transport.Validators.TableSchema do
  @moduledoc """
  Validate a file against a JSON Schema using [ex_json_schema](https://github.com/jonasschmidt/ex_json_schema).
  """
  # https://github.com/etalab/transport-site/issues/2390
  # Plan to move the other validator here as we deprecate
  # the previous validation flow.
  alias Shared.Validation.TableSchemaValidator.Wrapper, as: TableSchemaValidator
  @validator_version_key_name "validata-api-version"
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{
        id: resource_history_id,
        payload: %{"permanent_url" => url, "schema_name" => schema_name, "schema_version" => schema_version}
      })
      when is_binary(schema_name) do
    validation_result = perform_validation(schema_name, url, schema_version)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      command: TableSchemaValidator.validator_api_url(schema_name, url, schema_version),
      validator: validator_name(),
      result: validation_result |> normalize_validation_result(),
      resource_history_id: resource_history_id,
      validator_version: validation_result |> validator_version()
    }
    |> DB.Repo.insert!()

    :ok
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "validata-api"

  def perform_validation(schema_name, url, schema_version) do
    TableSchemaValidator.validate(schema_name, url, schema_version)
  end

  def normalize_validation_result(result) when is_map(result) do
    result
    |> Map.reject(fn {key, _value} -> key == @validator_version_key_name end)
    |> Map.put("validation_performed", true)
  end

  def normalize_validation_result(nil), do: %{"validation_performed" => false}

  def validator_version(%{@validator_version_key_name => validata_api_version}), do: validata_api_version
  def validator_version(nil), do: nil
end
