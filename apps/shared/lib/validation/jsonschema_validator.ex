defmodule Shared.Validation.JSONSchemaValidator.Wrapper do
  @moduledoc """
  This behaviour defines the API for a JSON Schema Validator
  """
  defp impl, do: Application.get_env(:transport, :jsonschema_validator_impl)

  @callback load_jsonschema_for_schema(binary()) :: ExJsonSchema.Schema.Root.t()
  def load_jsonschema_for_schema(schema_name), do: impl().load_jsonschema_for_schema(schema_name)

  @callback validate(ExJsonSchema.Schema.Root.t(), map() | binary()) :: map()
  def validate(schema, target), do: impl().validate(schema, target)
end

defmodule Shared.Validation.JSONSchemaValidator do
  @moduledoc """
  Works with JSON schemas:
  - load them from schema.data.gouv.fr
  - validate payloads
  """
  import Transport.Shared.Schemas
  @behaviour Shared.Validation.JSONSchemaValidator.Wrapper

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

  @impl true
  def load_jsonschema_for_schema(schema_name) do
    ensure_schema_is_jsonschema!(schema_name)
    schema_name |> read_latest_schema() |> ExJsonSchema.Schema.resolve()
  end

  def ensure_schema_is_jsonschema!(schema_name) do
    unless Enum.member?(json_schemas_names(), schema_name) do
      raise "#{schema_name} is not a JSONSchema"
    end
  end

  @impl true
  def validate(schema, url) when is_binary(url) do
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client().get(url, [], follow_redirect: true),
         {:ok, json} <- Jason.decode(body) do
      validate(schema, json)
    else
      _ -> nil
    end
  end

  @impl true
  def validate(schema, payload) do
    errors =
      case ExJsonSchema.Validator.validate(schema, payload, error_formatter: ErrorFormatter) do
        :ok -> []
        {:error, errors} -> errors
      end

    %{"has_errors" => not Enum.empty?(errors), "errors_count" => Enum.count(errors), "errors" => errors |> Enum.take(100)}
  end

  defp json_schemas_names, do: Map.keys(schemas_by_type("jsonschema"))
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
