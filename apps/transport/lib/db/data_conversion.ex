defmodule DB.DataConversion do
  @moduledoc """
  DataConversion stores metadata for data conversions from one format to another
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "data_conversion" do
    field(:status, Ecto.Enum, values: [:created, :pending, :success, :failed, :timeout])
    field(:converter, :string)
    field(:converter_version, :string)
    field(:convert_from, Ecto.Enum, values: [:GTFS])
    field(:convert_to, Ecto.Enum, values: [:GeoJSON, :NeTEx])
    field(:resource_history_uuid, Ecto.UUID)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(dc in DB.DataConversion, as: :data_conversion)

  @doc """
  NeTEx is no longer supported as a target format but it's kept in the schema to support legacy data and the cleanup job.
  """
  def available_conversion_formats,
    do:
      Ecto.Enum.values(DB.DataConversion, :convert_to)
      |> Enum.reject(&(&1 == :NeTEx))

  @doc """
  Finds the default converter to use for a target format.

  iex> converter_to_use(:GeoJSON)
  "rust-transit/gtfs-to-geojson"
  iex> available_conversion_formats() |> Enum.each(& converter_to_use/1)
  :ok
  """
  @spec converter_to_use(binary() | atom()) :: binary()
  def converter_to_use(convert_to) do
    Map.fetch!(
      %{
        "GeoJSON" => Transport.GTFSToGeoJSONConverter.converter()
      },
      to_string(convert_to)
    )
  end

  @spec join_resource_history_with_data_conversion(Ecto.Query.t(), [binary()], [binary()] | nil) :: Ecto.Query.t()
  @spec join_resource_history_with_data_conversion(Ecto.Query.t(), [binary()]) :: Ecto.Query.t()
  def join_resource_history_with_data_conversion(%Ecto.Query{} = query, convert_tos, converters \\ nil) do
    converters = converters || Enum.map(convert_tos, &converter_to_use/1)

    query
    |> join(:left, [resource_history: rh], dc in DB.DataConversion,
      on: fragment("(?->>'uuid')::uuid = ?", rh.payload, dc.resource_history_uuid),
      as: :data_conversion
    )
    |> where([data_conversion: dc], dc.convert_from == :GTFS and dc.convert_to in ^convert_tos)
    |> where([data_conversion: dc], dc.status == :success and dc.converter in ^converters)
  end

  @spec latest_data_conversions(integer(), binary()) :: [map()]
  def latest_data_conversions(dataset_id, convert_to) do
    DB.Dataset.base_query()
    |> DB.ResourceHistory.join_dataset_with_latest_resource_history()
    |> join_resource_history_with_data_conversion([convert_to])
    |> where([dataset: d, data_conversion: dc], d.id == ^dataset_id and dc.status == :success)
    |> select([resource_history: rh, data_conversion: dc], %{
      resource_history_id: rh.id,
      data_conversion_id: dc.id,
      s3_path: fragment("?->>'filename'", dc.payload)
    })
    |> DB.Repo.all()
  end

  @spec delete_data_conversions([map()]) :: :ok
  def delete_data_conversions(conversions) do
    Enum.each(conversions, fn %{data_conversion_id: dc_id, s3_path: s3_path} ->
      Transport.S3.delete_object!(:history, s3_path)
      DB.DataConversion |> DB.Repo.get(dc_id) |> DB.Repo.delete!()
    end)
  end
end
