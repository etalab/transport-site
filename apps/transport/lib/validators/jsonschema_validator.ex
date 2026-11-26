defmodule Transport.Validators.JSONSchema.Wrapper do
  @moduledoc """
  This behaviour defines the API for a JSON Schema Validator
  """
  defp impl, do: Application.get_env(:transport, :jsonschema_validator_impl)

  @callback load_jsonschema_for_schema(binary()) :: ExJsonSchema.Schema.Root.t()
  @callback load_jsonschema_for_schema(binary(), binary()) :: ExJsonSchema.Schema.Root.t()
  def load_jsonschema_for_schema(schema_name),
    do: impl().load_jsonschema_for_schema(schema_name)

  def load_jsonschema_for_schema(schema_name, schema_version),
    do: impl().load_jsonschema_for_schema(schema_name, schema_version)

  @callback validate(ExJsonSchema.Schema.Root.t(), map() | binary()) :: map() | nil
  def validate(schema, target), do: impl().validate(schema, target)
end

defmodule Transport.Validators.JSONSchema do
  @moduledoc """
  Validate a file against a JSON Schema using [ex_json_schema](https://github.com/jonasschmidt/ex_json_schema).
  """
  # https://github.com/etalab/transport-site/issues/2390
  # Plan to move the other validator here as we deprecate
  # the previous validation flow.
  alias Transport.Validators.JSONSchema.Wrapper, as: JSONSchemaValidator
  @behaviour Transport.Validators.Validator

  import Transport.Schemas
  @behaviour Transport.Validators.JSONSchema.Wrapper

  defmodule ErrorFormatter do
    @moduledoc """
    Format JSON Schema errors.

    See https://hexdocs.pm/ex_json_schema/readme.html#validation-error-formats
    """
    alias ExJsonSchema.Validator.Error

    @spec format(ExJsonSchema.Validator.errors()) :: [String.t()]
    def format(errors) do
      errors
      |> Enum.map(fn %Error{error: error, path: path} ->
        "#{path}: #{to_string(error)}"
      end)
    end
  end

  @impl true
  def load_jsonschema_for_schema(schema_name, schema_version \\ "latest") do
    ensure_schema_is_jsonschema!(schema_name)
    schema_name |> schema_url(schema_version) |> read_vendored_schema!() |> ExJsonSchema.Schema.resolve()
  end

  @doc """
  Reads the copy of a remote schema stored at `priv/vendored_schemas/<host>/<path>`, so that validation needs no
  network. Only the latest version of each JSON Schema is vendored, with the schemas it references.
  Also used by ExJsonSchema to resolve remote `$ref`s.
  """
  def read_vendored_schema!(url) do
    %URI{scheme: "https", host: host, path: path} = URI.parse(url)

    :transport
    |> Application.app_dir(Path.join(["priv/vendored_schemas", host, path]))
    |> File.read!()
    |> Jason.decode!()
  end

  def ensure_schema_is_jsonschema!(schema_name) do
    unless Enum.member?(json_schemas_names(), schema_name) do
      raise "#{schema_name} is not a JSONSchema"
    end
  end

  @impl true
  def validate(schema, url) when is_binary(url) do
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           http_client().get(url, [], follow_redirect: true, recv_timeout: 180_000),
         {:ok, json} <- Jason.decode(body) do
      validate(schema, json)
    else
      _ -> nil
    end
  end

  @impl true
  def validate(schema, payload) do
    errors =
      case ExJsonSchema.Validator.validate(schema, payload, error_formatter: ErrorFormatter) do
        :ok -> []
        {:error, errors} -> errors
      end

    %{
      "has_errors" => not Enum.empty?(errors),
      "errors_count" => Enum.count(errors),
      "errors" => errors |> Enum.take(100),
      "validator" => __MODULE__
    }
  end

  defp json_schemas_names, do: Map.keys(schemas_by_type("jsonschema"))
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{
        id: resource_history_id,
        payload: %{"permanent_url" => url, "schema_name" => schema_name, "schema_version" => schema_version} = payload
      })
      when is_binary(schema_name) do
    schema_version = schema_version || Map.get(payload, "latest_schema_version_to_date", "latest")

    result = perform_validation(schema_name, schema_version, url)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: result,
      digest: digest(result),
      resource_history_id: resource_history_id,
      validator_version: validator_version()
    }
    |> DB.Repo.insert!()

    :ok
  end

  def perform_validation(schema_name, schema_version, url) do
    schema_name
    |> JSONSchemaValidator.load_jsonschema_for_schema(schema_version)
    |> JSONSchemaValidator.validate(url)
    |> normalize_validation_result()
  end

  def normalize_validation_result(nil), do: %{"validation_performed" => false}

  def normalize_validation_result(%{"has_errors" => _, "errors_count" => _, "errors" => _} = validation),
    do: Map.merge(validation, %{"validation_performed" => true})

  @impl Transport.Validators.Validator
  def validator_name, do: "EXJSONSchema"
  def validator_version, do: to_string(Application.spec(:ex_json_schema, :vsn))

  @doc """
  iex> digest(%{"warnings_count" => 2, "errors_count" => 3, "issues" => []})
  %{"errors_count" => 3, "warnings_count" => 2}
  iex> digest(%{"issues" => []})
  %{}
  """
  def digest(validation_result) do
    Map.intersect(%{"warnings_count" => 0, "errors_count" => 0}, validation_result)
  end

  @impl Transport.Validators.Validator
  def outdated?(_multi_validation), do: nil
end
