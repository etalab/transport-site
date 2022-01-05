defmodule Transport.Shared.Schemas.Wrapper do
  @moduledoc """
  This behaviour defines the API for schemas
  """
  defp impl, do: Application.get_env(:transport, :schemas_impl)

  @callback schemas_by_type(binary()) :: map()
  def schemas_by_type(schema_name), do: impl().schemas_by_type(schema_name)

  @callback transport_schemas() :: map()
  def transport_schemas, do: impl().transport_schemas()
end

defmodule Transport.Shared.Schemas do
  @moduledoc """
  Load transport schemas listed on https://schema.data.gouv.fr
  """
  import Shared.Application, only: [cache_name: 0]
  @behaviour Transport.Shared.Schemas.Wrapper

  @schemas_catalog_url "https://schema.data.gouv.fr/schemas.yml"

  def read_latest_schema(schema_name) do
    comp_fn = fn ->
      schema = Map.fetch!(transport_schemas(), schema_name)

      %HTTPoison.Response{status_code: 200, body: body} =
        http_client().get!(schema_url(schema_name, schema["latest_version"]))

      Jason.decode!(body)
    end

    cache_fetch("latest_schema_#{schema_name}", comp_fn)
  end

  def schema_url(schema_name, schema_version) do
    "https://schema.data.gouv.fr/schemas/#{schema_name}/#{schema_version}/schema.json"
  end

  @impl true
  def schemas_by_type(schema_type) when schema_type in ["tableschema", "jsonschema"] do
    :maps.filter(fn _, v -> v["type"] == schema_type end, transport_schemas())
  end

  @impl true
  def transport_schemas do
    comp_fn = fn ->
      %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(@schemas_catalog_url)
      yaml = body |> YamlElixir.read_from_string!()
      :maps.filter(fn _, v -> v["email"] == Application.fetch_env!(:transport, :contact_email) end, yaml)
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
