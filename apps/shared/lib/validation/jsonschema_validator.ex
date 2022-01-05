defmodule Shared.Validation.JSONSchemaValidator do
  @moduledoc """
  Works with JSON schemas:
  - load them from schema.data.gouv.fr
  - validate payloads
  """
  import Transport.Shared.Schemas

  defmodule ErrorFormatter do
    @moduledoc """
    Format JSON Schema errors.

    See https://hexdocs.pm/ex_json_schema/readme.html#validation-error-formats
    """
    alias ExJsonSchema.Validator.Error

    @spec format(ExJsonSchema.Validator.errors()) :: [String.t()]
    def format(errors) do
      errors
      |> Enum.map(fn %Error{error: error, path: path} ->
        "#{path}: #{to_string(error)}"
      end)
    end
  end

  def load_jsonschema_for_schema(schema_name) do
    unless Enum.member?(json_schemas_names(), schema_name) do
      raise "#{schema_name} is not a JSONSchema"
    end

    schema_name |> read_latest_schema() |> ExJsonSchema.Schema.resolve()
  end

  @spec validate(ExJsonSchema.Schema.Root.t(), map()) :: map()
  def validate(schema, payload) do
    errors =
      case ExJsonSchema.Validator.validate(schema, payload, error_formatter: ErrorFormatter) do
        :ok -> []
        {:error, errors} -> errors
      end

    %{"has_errors" => not Enum.empty?(errors), "errors_count" => Enum.count(errors), "errors" => errors}
  end

  defp json_schemas_names, do: Map.keys(schemas_by_type("jsonschema"))
end
