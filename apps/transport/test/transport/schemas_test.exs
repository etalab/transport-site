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

  @tag :ci_only_on_mondays
  test "the catalog is up to date with schema.data.gouv.fr" do
    upstream =
      "#{@base_url}/schemas.json"
      |> get_json!()
      |> Map.fetch!("schemas")
      |> Enum.filter(&("transport.data.gouv.fr" in &1["labels"] and &1["schema_type"] != "datapackage"))
      |> Map.new(fn schema ->
        versions = Enum.map(schema["versions"], &Map.take(&1, ["version_name", "schema_url"]))
        {schema["name"], schema |> Map.take(["title", "schema_type"]) |> Map.put("versions", versions)}
      end)

    for name <- Enum.uniq(Map.keys(upstream) ++ Map.keys(transport_schemas())) do
      assert upstream[name] == transport_schemas()[name], """
      #{name} changed on schema.data.gouv.fr, update priv/transport_schemas.yml.
      For a new JSON Schema version, also vendor its file in priv/vendored_schemas.
      Upstream: #{inspect(upstream[name], pretty: true)}
      """
    end
  end

  @tag :ci_only_on_mondays
  test "vendored schemas are up to date" do
    dir = Application.app_dir(:transport, "priv/vendored_schemas")

    for path <- Path.wildcard("#{dir}/**/*.json") do
      url = "https://" <> Path.relative_to(path, dir)
      assert get_json!(url) == Transport.Validators.JSONSchema.read_vendored_schema!(url), "#{url} changed upstream"
    end
  end

  defp get_json!(url), do: url |> Req.get!(decode_body: false) |> Map.fetch!(:body) |> Jason.decode!()
end
