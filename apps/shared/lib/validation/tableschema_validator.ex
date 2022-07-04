defmodule Shared.Validation.TableSchemaValidator.Wrapper do
  @moduledoc """
  This behaviour defines the API for a Table Schema Validator
  """
  defp impl, do: Application.get_env(:transport, :tableschema_validator_impl)

  @callback validate(binary(), binary()) :: map() | nil
  @callback validate(binary(), binary(), binary()) :: map() | nil
  def validate(schema_name, url), do: impl().validate(schema_name, url)
  def validate(schema_name, url, schema_version), do: impl().validate(schema_name, url, schema_version)

  def validator_api_url(schema_name, url, schema_version),
    do: impl().validator_api_url(schema_name, url, schema_version)
end

defmodule Shared.Validation.TableSchemaValidator do
  @moduledoc """
  Works with table schemas:
  - load schemas from schema.data.gouv.fr
  - use the Validata API to validate remote resources
  """
  import Transport.Shared.Schemas
  @behaviour Shared.Validation.TableSchemaValidator.Wrapper
  @validata_api_url URI.parse("https://validata-api.app.etalab.studio/validate")
  # https://git.opendatafrance.net/validata/validata-core/-/blob/75ee5258010fc43b6a164122eff2579c2adc01a7/validata_core/helpers.py#L152
  @structure_tags ["#head", "#structure"]

  @impl true
  def validate(schema_name, url, schema_version \\ "latest") when is_binary(schema_name) and is_binary(url) do
    api_url = validator_api_url(schema_name, url, schema_version)

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client().get(api_url, []),
         {:ok, json} <- Jason.decode(body) do
      build_report(json)
    else
      _ -> nil
    end
  end

  @impl true
  def validator_api_url(schema_name, url, schema_version \\ "latest") when is_binary(schema_name) and is_binary(url) do
    ensure_schema_is_tableschema!(schema_name)

    schema_url = schema_url(schema_name, schema_version || "latest")

    # See https://go.validata.fr/api/v1/apidocs
    @validata_api_url
    |> Map.put(:query, URI.encode_query(%{schema: schema_url, url: url}))
    |> URI.to_string()
  end

  defp build_report(
         %{"report" => %{"tasks" => tasks}, "_meta" => %{"validata-api-version" => validata_api_version}} = payload
       ) do
    if Enum.count(tasks) != 1 do
      raise "tasks should have a length of 1 for response #{payload}"
    end

    raw_errors = hd(tasks)["errors"]
    # We count the errors on our side, because the error count given by the report can be wrong
    # see https://git.opendatafrance.net/validata/validata-core/-/issues/37
    nb_errors = Enum.count(raw_errors)

    {row_errors, structure_errors} =
      raw_errors |> Enum.split_with(&MapSet.disjoint?(MapSet.new(&1["tags"]), MapSet.new(@structure_tags)))

    structure_errors = structure_errors |> Enum.map(&~s(#{&1["name"]} : #{&1["message"]}))

    row_errors =
      row_errors
      |> Enum.map(fn row ->
        ~s(#{row["name"]} : colonne #{row["fieldName"]}, ligne #{row["rowPosition"]}. #{row["message"]})
      end)

    errors = (structure_errors ++ row_errors) |> Enum.take(100)

    %{
      "has_errors" => nb_errors > 0,
      "errors_count" => nb_errors,
      "errors" => errors,
      "validator" => __MODULE__,
      "validata_api_version" => validata_api_version
    }
  end

  defp build_report(_), do: nil

  defp ensure_schema_is_tableschema!(schema_name) do
    unless Enum.member?(tableschema_names(), schema_name) do
      raise "#{schema_name} is not a tableschema"
    end
  end

  defp tableschema_names, do: Map.keys(schemas_by_type("tableschema"))
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
