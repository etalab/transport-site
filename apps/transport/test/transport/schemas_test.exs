defmodule Transport.SchemasTest do
  use ExUnit.Case, async: false
  import Transport.Schemas
  import Mox

  setup :verify_on_exit!

  @base_url "https://schema.data.gouv.fr"

  setup do
    setup_schemas_response()
    Cachex.clear(Transport.Application.cache_name())
    on_exit(fn -> Cachex.clear(Transport.Application.cache_name()) end)
    Mox.stub_with(Transport.Schemas.Mock, Transport.Schemas)
    :ok
  end

  test "transport_schemas" do
    assert ["etalab/schema-amenagements-cyclables", "etalab/schema-lieux-covoiturage", "etalab/schema-zfe"] ==
             Map.keys(transport_schemas())

    assert_cache_key_has_ttl("transport_schemas")
  end

  test "schemas_by_type" do
    assert ["etalab/schema-amenagements-cyclables", "etalab/schema-zfe"] == Map.keys(schemas_by_type("jsonschema"))
    assert ["etalab/schema-lieux-covoiturage"] == Map.keys(schemas_by_type("tableschema"))
  end

  describe "schema_url" do
    test "simple case" do
      assert "#{@base_url}/schemas/etalab/schema-zfe/0.7.2/schema.json" ==
               schema_url("etalab/schema-zfe", "latest")

      assert "#{@base_url}/schemas/etalab/schema-zfe/0.7.2/schema.json" ==
               schema_url("etalab/schema-zfe", "0.7.2")
    end

    test "with a custom schema filename" do
      assert "#{@base_url}/schemas/etalab/schema-amenagements-cyclables/0.3.3/schema_amenagements_cyclables.json" ==
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

  defp setup_schemas_response do
    url = "https://schema.data.gouv.fr/schemas.json"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      %HTTPoison.Response{body: File.read!("#{__DIR__}/../fixture/schemas/schemas.json"), status_code: 200}
    end)
  end

  def assert_cache_key_has_ttl(cache_key, expected_ttl \\ 300) do
    assert_in_delta Cachex.ttl!(Transport.Application.cache_name(), cache_key),
                    :timer.seconds(expected_ttl),
                    :timer.seconds(1)
  end
end
