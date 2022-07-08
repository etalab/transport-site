defmodule Transport.Validators.EXJSONSchema do
  @moduledoc """
  Validate a file against a JSON Schema using [ex_json_schema](https://github.com/jonasschmidt/ex_json_schema).
  """
  # https://github.com/etalab/transport-site/issues/2390
  # Plan to move the other validator here as we deprecate
  # the previous validation flow.
  alias Shared.Validation.JSONSchemaValidator.Wrapper, as: JSONSchemaValidator
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{
        id: resource_history_id,
        payload: %{"permanent_url" => url, "schema_name" => schema_name}
      })
      when is_binary(schema_name) do
    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: perform_validation(schema_name, url),
      resource_history_id: resource_history_id,
      validator_version: validator_version()
    }
    |> DB.Repo.insert!()

    :ok
  end

  def perform_validation(schema_name, url) do
    schema_name
    |> JSONSchemaValidator.load_latest_jsonschema_for_schema()
    |> JSONSchemaValidator.validate(url)
    |> normalize_validation_result()
  end

  def normalize_validation_result(nil), do: %{"validation_performed" => false}

  def normalize_validation_result(%{"has_errors" => _, "errors_count" => _, "errors" => _} = validation),
    do: Map.merge(validation, %{"validation_performed" => true})

  @impl Transport.Validators.Validator
  def validator_name, do: "EXJSONSchema"
  def validator_version, do: to_string(Application.spec(:ex_json_schema, :vsn))
end
