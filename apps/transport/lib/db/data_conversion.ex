defmodule DB.DataConversion do
  @moduledoc """
  DataConversion stores metadata for data conversions from one format to another
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "data_conversion" do
    field(:convert_from, Ecto.Enum, values: [:GTFS])
    field(:convert_to, Ecto.Enum, values: [:GeoJSON, :NeTEx])
    field(:resource_history_uuid, Ecto.UUID)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(dc in DB.DataConversion, as: :data_conversion)

  def join_resource_history_with_data_conversion(query, list_of_convert_to) do
    query
    |> join(:left, [resource_history: rh], dc in DB.DataConversion,
      on: fragment("(?->>'uuid')::uuid = ?", rh.payload, dc.resource_history_uuid),
      as: :data_conversion
    )
    |> where([data_conversion: dc], dc.convert_to in ^list_of_convert_to)
  end

  def last_data_conversions(dataset_id, convert_to) do
    DB.Dataset.base_query()
    |> DB.ResourceHistory.join_dataset_with_latest_resource_history()
    |> join_resource_history_with_data_conversion([convert_to])
    |> where([dataset: d], d.id == ^dataset_id)
    |> select([resource_history: rh, data_conversion: dc], %{
      resource_history_id: rh.id,
      data_conversion_id: dc.id,
      s3_path: fragment("?->>'filename'", dc.payload)
    })
    |> DB.Repo.all()
  end

  def delete_data_conversions(conversions) do
    conversions
    |> Enum.each(fn %{data_conversion_id: dc_id, s3_path: s3_path} ->
      Transport.S3.delete_object!(:history, s3_path)
      DB.DataConversion |> DB.Repo.get(dc_id) |> DB.Repo.delete!()
    end)
  end

  def force_refresh_netex_conversions(dataset_id) do
    conversions = last_data_conversions(dataset_id, "NeTEx")
    delete_data_conversions(conversions)

    conversions
    |> Enum.each(fn %{resource_history_id: rh_id} ->
      %{"resource_history_id" => rh_id}
      |> Transport.Jobs.SingleGtfsToNetexConverterJob.new()
      |> Oban.insert()
    end)
  end
end
