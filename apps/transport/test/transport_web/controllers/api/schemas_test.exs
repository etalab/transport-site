defmodule TransportWeb.API.SchemasTest do
  use ExUnit.Case
  import OpenApiSpex.TestAssertions

  test "make sure we get a warning because this helps keeping specs in sync with API output" do
    api_spec = TransportWeb.API.Spec.spec()

    api_spec.components.schemas
    |> Enum.filter(fn {_name, schema} -> schema.type == :object end)
    # composable type
    |> Enum.reject(fn {name, _schema} -> name == "GeometryBase" end)
    |> Enum.each(fn {name, schema} ->
      assert schema.additionalProperties == false,
             "\"#{name}\" OpenAPI spec declaration lacks additionalProperties: false"
    end)
  end
end
