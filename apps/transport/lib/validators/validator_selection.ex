defmodule Transport.ValidatorsSelection do
  @moduledoc """
  behavior for Transport.ValidatorsSelection.Impl
  """
  @callback validators(DB.ResourceHistory.t() | DB.Resource.t() | map()) :: list()
  @callback validators_for_feature(atom()) :: [Transport.Validators.Validator.t()]

  def validators(value), do: impl().validators(value)
  def validators_for_feature(feature), do: impl().validators_for_feature(feature)

  def impl, do: Application.get_env(:transport, :validator_selection)
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

  @impl Transport.ValidatorsSelection
  def validators_for_feature(feature)
      when feature in [
             :expiration_notification,
             :datasets_without_gtfs_rt_related_resouces,
             :gtfs_import_stops_job,
             :api_datasets_controller,
             :api_stats_controller,
             :aoms_controller,
             :backoffice_page_controller,
             :gtfs_rt_validator
           ],
      do: [
        Transport.Validators.GTFSTransport,
        Transport.Validators.MobilityDataGTFSValidator
      ]

  def validators_for_feature(:multi_validation_with_error_static_validators),
    do: [
      Transport.Validators.GTFSTransport,
      Transport.Validators.TableSchema,
      Transport.Validators.EXJSONSchema,
      Transport.Validators.MobilityDataGTFSValidator
    ]

  def validators_for_feature(:multi_validation_with_error_realtime_validators),
    do: [
      Transport.Validators.GBFSValidator
    ]

  def validators_for_feature(:stats_compute_aom_gtfs_max_severity), do: [Transport.Validators.GTFSTransport]

  def validators_for_feature(feature) when feature in [:dataset_controller, :resource_controller],
    do: [
      Transport.Validators.GTFSTransport,
      Transport.Validators.GTFSRT,
      Transport.Validators.TableSchema,
      Transport.Validators.EXJSONSchema,
      Transport.Validators.GBFSValidator,
      Transport.Validators.NeTEx.Validator,
      Transport.Validators.MobilityDataGTFSValidator
    ]

  defp netex_validator_enabled?, do: !Application.fetch_env!(:transport, :disable_netex_validator)
end
