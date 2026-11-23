defmodule Transport.SchemasTest do
  use ExUnit.Case, async: false
  import Transport.Schemas
  import Mox

  setup :verify_on_exit!

  @base_url "https://schema.data.gouv.fr"

  setup do
    Mox.stub_with(Transport.Schemas.Mock, Transport.Schemas)
    :ok
  end

  test "transport_schemas" do
    assert %{
             "title" => "Zone à Faibles Emissions",
             "schema_type" => "jsonschema",
             "versions" => [
               %{"version_name" => "0.6.1", "schema_url" => "#{@base_url}/schemas/etalab/schema-zfe/0.6.1/schema.json"}
               | _
             ]
           } = Map.fetch!(transport_schemas(), "etalab/schema-zfe")
  end

  test "schemas_by_type" do
    assert ["etalab/schema-amenagements-cyclables", "etalab/schema-zfe"] == Map.keys(schemas_by_type("jsonschema"))
    assert "etalab/schema-lieux-covoiturage" in Map.keys(schemas_by_type("tableschema"))
  end

  describe "schema_url" do
    test "simple case" do
      assert "#{@base_url}/schemas/etalab/schema-zfe/0.8.2/schema.json" ==
               schema_url("etalab/schema-zfe", "latest")

      assert "#{@base_url}/schemas/etalab/schema-zfe/0.7.2/schema.json" ==
               schema_url("etalab/schema-zfe", "0.7.2")
    end

    test "with a custom schema filename" do
      assert "#{@base_url}/schemas/etalab/schema-amenagements-cyclables/0.3.5/schema_amenagements_cyclables.json" ==
               schema_url("etalab/schema-amenagements-cyclables", "latest")
    end

    test "makes sure schema and version are valid" do
      assert_raise KeyError, ~r(^key "foo" not found in), fn ->
        schema_url("foo", "latest")
      end

      assert_raise KeyError, "foo is not a valid version for etalab/schema-zfe", fn ->
        schema_url("etalab/schema-zfe", "foo")
      end
    end
  end

  describe "documentation_url" do
    test "with only a schema_name" do
      assert "https://schema.data.gouv.fr/etalab/schema-zfe/" == documentation_url("etalab/schema-zfe")
    end

    test "with a schema_name and a schema_version" do
      assert "https://schema.data.gouv.fr/etalab/schema-zfe/0.7.2/" == documentation_url("etalab/schema-zfe", "0.7.2")
    end

    test "makes sure schema and version are valid" do
      assert_raise KeyError, ~r(^key "foo" not found in), fn ->
        documentation_url("foo", "latest")
      end

      assert_raise KeyError, "foo is not a valid version for etalab/schema-zfe", fn ->
        documentation_url("etalab/schema-zfe", "foo")
      end
    end
  end
end
