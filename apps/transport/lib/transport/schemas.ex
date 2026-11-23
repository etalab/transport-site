defmodule Transport.Schemas.Wrapper do
  @moduledoc """
  This behaviour defines the API for schemas
  """
  defp impl, do: Application.get_env(:transport, :schemas_impl)

  @callback schemas_by_type(binary()) :: map()
  def schemas_by_type(type), do: impl().schemas_by_type(type)

  @callback transport_schemas() :: map()
  def transport_schemas, do: impl().transport_schemas()

  def known_schema?(schema_name), do: Map.has_key?(transport_schemas(), schema_name)

  def schema_type(schema_name) do
    cond do
      tableschema?(schema_name) -> "tableschema"
      jsonschema?(schema_name) -> "jsonschema"
    end
  end

  def tableschema?(schema_name) do
    Map.has_key?(schemas_by_type("tableschema"), schema_name)
  end

  def jsonschema?(schema_name) do
    Map.has_key?(schemas_by_type("jsonschema"), schema_name)
  end

  @doc """
  Get the latest version for a given schema name.
  """
  def latest_version(schema_name) when is_binary(schema_name) do
    schema_name |> schema_versions() |> Enum.at(-1)
  end

  @doc """
  Fetches all the version numbers for a given schema name.
  """
  def schema_versions(schema_name) when is_binary(schema_name) do
    transport_schemas()
    |> Map.fetch!(schema_name)
    |> Map.fetch!("versions")
    |> Enum.map(& &1["version_name"])
  end
end

defmodule Transport.Schemas do
  @moduledoc """
  Transport schemas from https://schema.data.gouv.fr, listed in `priv/transport_schemas.yml`
  """
  alias Transport.Schemas.Wrapper
  @behaviour Transport.Schemas.Wrapper

  @catalog_path Path.join(__DIR__, "../../priv/transport_schemas.yml")
  @external_resource @catalog_path
  @transport_schemas @catalog_path
                     |> YamlElixir.read_from_file!()
                     |> Map.new(fn {name, %{"schema_file" => schema_file, "versions" => versions} = schema} ->
                       versions =
                         Enum.map(versions, fn version ->
                           %{
                             "version_name" => version,
                             "schema_url" => "https://schema.data.gouv.fr/schemas/#{name}/#{version}/#{schema_file}"
                           }
                         end)

                       {name, schema |> Map.take(["title", "schema_type"]) |> Map.put("versions", versions)}
                     end)

  def schema_url(schema_name, schema_version) do
    schema = Map.fetch!(Wrapper.transport_schemas(), schema_name)

    schema_version = if schema_version == "latest", do: Wrapper.latest_version(schema_name), else: schema_version

    unless Enum.member?(Wrapper.schema_versions(schema_name), schema_version) do
      raise KeyError, "#{schema_version} is not a valid version for #{schema_name}"
    end

    Map.fetch!(
      Enum.find(Map.fetch!(schema, "versions"), &(Map.fetch!(&1, "version_name") == schema_version)),
      "schema_url"
    )
  end

  def documentation_url(schema_name), do: documentation_url(schema_name, nil)

  def documentation_url(schema_name, nil = _schema_version) do
    _ = Map.fetch!(Wrapper.transport_schemas(), schema_name)
    "https://schema.data.gouv.fr/#{schema_name}/"
  end

  def documentation_url(schema_name, schema_version) when not is_nil(schema_version) do
    _ = Map.fetch!(Wrapper.transport_schemas(), schema_name)

    unless Enum.member?(Wrapper.schema_versions(schema_name), schema_version) do
      raise KeyError, "#{schema_version} is not a valid version for #{schema_name}"
    end

    "https://schema.data.gouv.fr/#{schema_name}/#{schema_version}/"
  end

  @impl true
  def schemas_by_type(schema_type) when schema_type in ["tableschema", "jsonschema"] do
    :maps.filter(fn _, v -> v["schema_type"] == schema_type end, Wrapper.transport_schemas())
  end

  @impl true
  def transport_schemas, do: @transport_schemas
end
