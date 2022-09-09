defmodule Transport.ValidatorsSelection do
  @moduledoc """
  behavior for Transport.ValidatorsSelection.Impl
  """
  @callback validators(DB.ResourceHistory.t() | DB.Resource.t() | map()) :: list()

  def impl, do: Application.get_env(:transport, :validator_selection)

  def validators(value), do: impl().validators(value)
end

defmodule Transport.ValidatorsSelection.Impl do
  @moduledoc """
  Lists which validators should run for a `DB.Resource` or `DB.ResourceHistory`
  """
  @behaviour Transport.ValidatorsSelection
  alias Transport.Shared.Schemas.Wrapper, as: Schemas
  alias Transport.Validators

  @spec formats_and_validators :: map()
  def formats_and_validators do
    %{
      "GTFS" => [Validators.GTFSTransport],
      "gtfs-rt" => [Validators.GTFSRT],
      "gbfs" => [Validators.GBFSValidator]
    }
  end

  @doc """
  Get a list of validators to run for a `DB.ResourceHistory`, `DB.Resource`, a map of format and schema or just a format
  """
  @impl Transport.ValidatorsSelection
  @spec validators(binary() | DB.ResourceHistory.t() | DB.Resource.t() | map()) :: list()
  def validators(%DB.ResourceHistory{payload: payload}) do
    validators(%{format: Map.get(payload, "format"), schema_name: Map.get(payload, "schema_name")})
  end

  def validators(%DB.Resource{format: format, schema_name: schema_name}) do
    validators(%{format: format, schema_name: schema_name})
  end

  def validators(%{format: format, schema_name: schema_name}) do
    validators = validators(format)

    if Enum.empty?(validators) and not is_nil(schema_name) do
      validators_for_schema(schema_name)
    else
      validators
    end
  end

  def validators(format) do
    format |> get_validators(formats_and_validators())
  end

  defp validators_for_schema(schema_name) do
    cond do
      Schemas.is_tableschema?(schema_name) ->
        [Transport.Validators.TableSchema]

      Schemas.is_jsonschema?(schema_name) ->
        [Transport.Validators.EXJSONSchema]

      true ->
        []
    end
  end

  @doc """
  iex> validators("GBFS", %{"GBFS" => ["v1", "v2"], "GTFS" => ["v3"]})
  ["v1", "v2"]
  iex> validators("GBFS", %{"GTFS" => ["v1"]})
  []
  """
  def get_validators(format, formats_and_validators) do
    formats_and_validators |> Map.get(format, [])
  end
end
