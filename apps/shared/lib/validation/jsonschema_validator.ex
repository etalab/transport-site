defmodule Shared.Validation.JSONSchemaValidator do
  @moduledoc """
  Works with JSON schemas:
  - load them from schema.data.gouv.fr
  - validate payloads
  """
  import Transport.Shared.Schemas

  def load_jsonschema_for_schema(schema_name) do
    unless Enum.member?(json_schemas_names(), schema_name) do
      raise "#{schema_name} is not a JSONSchema"
    end

    schema_name |> read_latest_schema() |> ExJsonSchema.Schema.resolve()
  end

  defp json_schemas_names, do: Map.keys(schemas_by_type("jsonschema"))
end
