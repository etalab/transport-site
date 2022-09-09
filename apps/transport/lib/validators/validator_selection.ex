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
  def validators(%DB.ResourceHistory{payload: payload}) do
    validators(%{format: Map.get(payload, "format"), schema_name: Map.get(payload, "schema_name")})
  end

  def validators(%DB.Resource{format: format, schema_name: schema_name}) do
    validators(%{format: format, schema_name: schema_name})
  end

  def validators(%{format: "GTFS"}), do: [Validators.GTFSTransport]
  def validators(%{format: "gtfs-rt"}), do: [Validators.GTFSRT]
  def validators(%{format: "gbfs"}), do: [Validators.GBFSValidator]

  def validators(%{schema_name: schema_name}) do
    cond do
      Schemas.is_tableschema?(schema_name) ->
        [Transport.Validators.TableSchema]

      Schemas.is_jsonschema?(schema_name) ->
        [Transport.Validators.EXJSONSchema]

      true ->
        []
    end
  end
end
