defmodule Shared.Validation.TableSchemaValidator.Wrapper do
  @moduledoc """
  This behaviour defines the API for a Table Schema Validator
  """
  defp impl, do: Application.get_env(:transport, :tableschema_validator_impl)

  @callback validate(binary(), binary()) :: map()
  @callback validate(binary(), binary(), binary()) :: map()
  def validate(schema_name, url), do: impl().validate(schema_name, url)
  def validate(schema_name, url, schema_version), do: impl().validate(schema_name, url, schema_version)
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

  @impl true
  def validate(schema_name, url, schema_version \\ "latest") when is_binary(schema_name) and is_binary(url) do
    ensure_schema_is_tableschema!(schema_name)

    schema_url = schema_url(schema_name, schema_version || "latest")

    # See https://go.validata.fr/api/v1/apidocs
    api_url =
      @validata_api_url
      |> Map.put(:query, URI.encode_query(%{schema: schema_url, url: url}))
      |> URI.to_string()

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client().get(api_url, []),
         {:ok, json} <- Jason.decode(body) do
      build_report(json)
    else
      _ -> nil
    end
  end

  defp build_report(%{"report" => %{"stats" => stats, "tasks" => tasks}} = report) do
    nb_errors = Map.fetch!(stats, "errors")

    if Enum.count(tasks) != 1 do
      raise "tasks should have a length of 1 for report #{report}"
    end

    raw_errors = hd(tasks)["errors"]

    {row_errors, structure_errors} = raw_errors |> Enum.split_with(&Enum.member?(&1["tags"], "#row"))

    structure_errors = structure_errors |> Enum.map(&~s(#{&1["name"]} : #{&1["message"]}))

    row_errors =
      row_errors
      |> Enum.map(fn row ->
        ~s(#{row["name"]} : colonne #{row["fieldName"]}, ligne #{row["rowPosition"]}. #{row["message"]})
      end)

    %{"has_errors" => nb_errors > 0, "errors_count" => nb_errors, "errors" => structure_errors ++ row_errors}
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
