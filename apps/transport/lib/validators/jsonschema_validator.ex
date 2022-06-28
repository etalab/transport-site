defmodule Transport.Validators.EXJSONSchema do
  @moduledoc """
  Validate a file against a JSON Schema using [ex_json_schema](https://github.com/jonasschmidt/ex_json_schema).
  """
  alias Shared.Validation.JSONSchemaValidator.Wrapper, as: JSONSchemaValidator
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{
        id: resource_history_id,
        payload: %{"permanent_url" => url, "schema_name" => schema_name}
      })
      when is_binary(schema_name) do
    validation_result =
      schema_name
      |> JSONSchemaValidator.load_jsonschema_for_schema()
      |> JSONSchemaValidator.validate(url)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: validation_result,
      resource_history_id: resource_history_id,
      validator_version: validator_version()
    }
    |> DB.Repo.insert!()

    :ok
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "EXJSONSchema"
  def validator_version, do: to_string(Application.spec(:ex_json_schema, :vsn))
end
