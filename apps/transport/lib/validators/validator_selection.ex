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

  @doc """
  Get a list of validators to run for a `DB.ResourceHistory`, `DB.Resource`, a map of format and schema
  """
  @impl Transport.ValidatorsSelection
  @spec validators(DB.ResourceHistory.t() | DB.Resource.t() | map()) :: list()
  def validators(%DB.ResourceHistory{payload: payload} = resource_history) do
    if DB.ResourceHistory.gtfs_flex?(resource_history) do
      [Transport.Validators.MobilityDataGTFSValidator]
    else
      validators(%{format: Map.get(payload, "format"), schema_name: Map.get(payload, "schema_name")})
    end
  end

  def validators(%DB.Resource{format: format, schema_name: schema_name}) do
    validators(%{format: format, schema_name: schema_name})
  end

  def validators(%{format: "GTFS"}), do: [Validators.GTFSTransport]
  def validators(%{format: "gtfs-rt"}), do: [Validators.GTFSRT]
  def validators(%{format: "gbfs"}), do: [Validators.GBFSValidator]

  def validators(%{format: "NeTEx"}) do
    if netex_validator_enabled?() do
      [Validators.NeTEx.Validator]
    else
      []
    end
  end

  def validators(%{schema_name: schema_name}) when not is_nil(schema_name) do
    cond do
      Schemas.tableschema?(schema_name) ->
        [Transport.Validators.TableSchema]

      Schemas.jsonschema?(schema_name) ->
        [Transport.Validators.EXJSONSchema]

      true ->
        []
    end
  end

  def validators(_), do: []

  defp netex_validator_enabled?, do: !Application.fetch_env!(:transport, :disable_netex_validator)
end
