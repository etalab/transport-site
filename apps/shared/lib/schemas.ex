defmodule Transport.Shared.Schemas.Wrapper do
  @moduledoc """
  This behaviour defines the API for schemas
  """
  defp impl, do: Application.get_env(:transport, :schemas_impl)

  @callback schemas_by_type(binary()) :: map()
  def schemas_by_type(type), do: impl().schemas_by_type(type)

  @callback transport_schemas() :: map()
  def transport_schemas, do: impl().transport_schemas()

  def is_known_schema?(schema_name), do: Map.has_key?(transport_schemas(), schema_name)

  def schema_type(schema_name) do
    cond do
      is_tableschema?(schema_name) -> "tableschema"
      is_jsonschema?(schema_name) -> "jsonschema"
    end
  end

  def is_tableschema?(schema_name) do
    Map.has_key?(schemas_by_type("tableschema"), schema_name)
  end

  def is_jsonschema?(schema_name) do
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

defmodule Transport.Shared.Schemas do
  @moduledoc """
  Load transport schemas listed on https://schema.data.gouv.fr
  """
  import Shared.Application, only: [cache_name: 0]
  alias Transport.Shared.Schemas.Wrapper
  @behaviour Transport.Shared.Schemas.Wrapper

  @schemas_catalog_url "https://schema.data.gouv.fr/schemas.json"

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

  @impl true
  def schemas_by_type(schema_type) when schema_type in ["tableschema", "jsonschema"] do
    :maps.filter(fn _, v -> v["schema_type"] == schema_type end, Wrapper.transport_schemas())
  end

  @impl true
  def transport_schemas do
    comp_fn = fn ->
      %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(@schemas_catalog_url)

      body
      |> Jason.decode!()
      |> Map.fetch!("schemas")
      |> Enum.filter(&Enum.member?(&1["labels"], "transport.data.gouv.fr"))
      |> Enum.into(%{}, fn schema -> {Map.fetch!(schema, "name"), schema} end)
    end

    cache_fetch("transport_schemas", comp_fn)
  end

  def cache_fetch(cache_key, comp_fn, ttl \\ 300) do
    {operation, result} = Cachex.fetch(cache_name(), cache_key, fn _ -> {:commit, comp_fn.()} end)

    case operation do
      :ok ->
        result

      :commit ->
        {:ok, true} = Cachex.expire(cache_name(), cache_key, :timer.seconds(ttl))
        result
    end
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
