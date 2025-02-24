defmodule Shared.Validation.TableSchemaValidator.Wrapper do
  @moduledoc """
  This behaviour defines the API for a Table Schema Validator
  """
  defp impl, do: Application.get_env(:transport, :tableschema_validator_impl)

  @callback validate(binary(), binary()) :: map() | :source_error | nil
  @callback validate(binary(), binary(), binary()) :: map() | :source_error | nil
  def validate(schema_name, url), do: impl().validate(schema_name, url)
  def validate(schema_name, url, schema_version), do: impl().validate(schema_name, url, schema_version)

  @callback validator_api_url(binary(), binary(), binary()) :: binary()
  def validator_api_url(schema_name, url, schema_version) do
    impl().validator_api_url(schema_name, url, schema_version)
  end
end

defmodule Shared.Validation.TableSchemaValidator do
  @moduledoc """
  Works with table schemas:
  - load schemas from schema.data.gouv.fr
  - use the Validata API to validate remote resources
  """
  import Transport.Shared.Schemas
  @behaviour Shared.Validation.TableSchemaValidator.Wrapper

  @timeout 180_000
  @max_nb_errors 100
  @validata_web_url URI.parse("https://validata.fr/table-schema")
  @validata_api_url URI.parse("https://api.validata.etalab.studio/validate")
  # https://gitlab.com/validata-table/validata-table/-/blob/main/src/validata_core/domain/helpers.py#L57
  @structure_tags MapSet.new(["#structure", "#header"])

  @impl true
  def validate(schema_name, url, schema_version \\ "latest") when is_binary(schema_name) and is_binary(url) do
    api_url = validator_api_url(schema_name, url, schema_version)

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           http_client().get(api_url, [], recv_timeout: @timeout),
         {:ok, json} <- Jason.decode(body) do
      Appsignal.increment_counter("validata.success", 1)
      build_report(json)
    else
      _ ->
        Appsignal.increment_counter("validata.failed", 1, %{
          schema_name: schema_name,
          schema_version: schema_version,
          url: url
        })

        nil
    end
  end

  @impl true
  def validator_api_url(schema_name, url, schema_version \\ "latest") when is_binary(schema_name) and is_binary(url) do
    ensure_schema_is_tableschema!(schema_name)

    schema_url = schema_url(schema_name, schema_version || "latest")

    # See https://api.validata.etalab.studio/apidocs
    @validata_api_url
    |> Map.put(:query, URI.encode_query(%{schema: schema_url, url: url, header_case: "false"}))
    |> URI.to_string()
  end

  def validata_web_url(schema_name) do
    ensure_schema_is_tableschema!(schema_name)

    @validata_web_url
    |> Map.put(:query, URI.encode_query(%{schema_name: "schema-datagouvfr.#{schema_name}"}))
    |> URI.to_string()
  end

  defp build_report(%{
         "report" => %{"valid" => valid, "stats" => %{"errors" => nb_errors}, "errors" => errors},
         "version" => validata_version
       }) do
    {structure_errors, row_errors} = Enum.split_with(errors, &structure_error?/1)

    structure_errors = Enum.map(structure_errors, & &1["message"])

    row_errors =
      Enum.map(row_errors, fn row ->
        ~s(#{row["message"]} Colonne `#{row["fieldName"]}`, ligne #{row["rowNumber"]}.)
      end)

    errors = (structure_errors ++ row_errors) |> Enum.take(@max_nb_errors)

    %{
      "has_errors" => not valid,
      "errors_count" => nb_errors,
      "errors" => errors,
      "validator" => __MODULE__,
      "validata_api_version" => validata_version
    }
  end

  # When the remote file cannot be loaded/is a 404
  defp build_report(%{"error" => %{"type" => "source-error"}}), do: :source_error

  defp build_report(_), do: nil

  defp structure_error?(%{"tags" => tags, "type" => type} = _row) do
    has_structure_tags = not MapSet.disjoint?(MapSet.new(tags), @structure_tags)
    # May not need to rely on error type in the future.
    # https://gitlab.com/validata-table/validata-table/-/issues/154
    eligible_error_type = type in ["check-error"]
    has_structure_tags or eligible_error_type
  end

  defp ensure_schema_is_tableschema!(schema_name) do
    unless Enum.member?(tableschema_names(), schema_name) do
      raise "#{schema_name} is not a tableschema"
    end
  end

  defp tableschema_names, do: Map.keys(schemas_by_type("tableschema"))
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
