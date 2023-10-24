defmodule Transport.Jobs.GTFSToNeTExEnRouteConverterJob do
  use Oban.Worker, max_attempts: 3, unique: [period: :infinity, fields: [:args, :queue, :worker]]
  alias Transport.Converters.GTFSToNeTExEnRoute
  import Ecto.Query

  @impl true
  def perform(%Oban.Job{args: %{"action" => "create", "resource_history_id" => resource_history_id}}) do
    %DB.ResourceHistory{payload: %{"permanent_url" => permanent_url, "uuid" => rh_uuid}} =
      resource_history = DB.Repo.get!(DB.ResourceHistory, resource_history_id)

    unless conversion_exists?(resource_history) do
      tmp_filepath = tmp_path(resource_history)

      try do
        Req.get!(permanent_url, compressed: false, into: File.stream!(tmp_filepath))
        conversion_id = GTFSToNeTExEnRoute.create_gtfs_to_netex_conversion(tmp_filepath)

        %DB.DataConversion{id: data_conversion_id} =
          %DB.DataConversion{
            convert_from: :GTFS,
            convert_to: :NeTEx,
            status: :created,
            converter: converter(),
            converter_version: converter_version(),
            resource_history_uuid: rh_uuid,
            payload: %{converter: %{id: conversion_id}}
          }
          |> DB.Repo.insert!()

        %{"action" => "poll", "data_conversion_id" => data_conversion_id, "attempt" => 1}
        |> __MODULE__.new()
        |> Oban.insert!()

        :ok
      after
        File.rm(tmp_filepath)
      end
    else
      {:discard, "An #{converter()} conversion already exists for ResourceHistory##{resource_history_id}"}
    end
  end

  @impl true
  def perform(%Oban.Job{
        args: %{"action" => "poll", "data_conversion_id" => data_conversion_id, "attempt" => attempt} = job_args
      }) do
    %DB.DataConversion{status: status, payload: %{"converter" => %{"id" => conversion_id}}} =
      data_conversion = DB.Repo.get!(DB.DataConversion, data_conversion_id)

    if status in [:created, :pending] do
      case GTFSToNeTExEnRoute.get_conversion(conversion_id) do
        {:pending, %{}} = return ->
          update_data_conversion!(data_conversion, return, attempt)

          job_args
          |> Map.replace!("attempt", attempt + 1)
          |> __MODULE__.new(schedule_in: next_polling_attempt_seconds(attempt))
          |> Oban.insert!()

        {:success, %{}} = return ->
          update_data_conversion!(data_conversion, return, attempt)

          %{"action" => "download", "data_conversion_id" => data_conversion_id}
          |> __MODULE__.new()
          |> Oban.insert!()

        {:failed, %{}} = return ->
          update_data_conversion!(data_conversion, return, attempt)
      end
    else
      {:discard,
       "Unexpected status for DataConversion##{data_conversion_id}. It should be created or pending. #{inspect(data_conversion)}"}
    end
  end

  @spec update_data_conversion!(DB.DataConversion.t(), {atom(), map()}, pos_integer()) :: DB.DataConversion.t()
  defp update_data_conversion!(
         %DB.DataConversion{payload: payload} = data_conversion,
         {status, %{} = converter_result},
         attempt
       ) do
    new_payload =
      Map.replace!(payload, "converter", Map.merge(converter_result, %{"id" => conversion_id, "attempt" => attempt}))

    data_conversion
    |> Ecto.Changeset.change(%{payload: new_payload, status: status})
    |> DB.Repo.update!()
  end

  def next_polling_attempt_seconds(current_attempt) when current_attempt < 12, do: 10
  def next_polling_attempt_seconds(current_attempt) when current_attempt >= 13, do: 30

  defp conversion_exists?(%DB.ResourceHistory{payload: %{"uuid" => rh_uuid}}) do
    converter = converter()

    DB.DataConversion.base_query()
    |> where(
      [data_conversion: dc],
      dc.resource_history_uuid == ^rh_uuid and dc.convert_from == :GTFS and dc.convert_to == :NeTEx and
        dc.converter == ^converter
    )
    |> DB.Repo.exists?()
  end

  defp tmp_path(%DB.ResourceHistory{id: id}) do
    System.tmp_dir!() |> Path.join("conversion_gtfs_netex_enroute_#{id}}")
  end

  def converter, do: "enroute/gtfs-to-netex"
  def converter_version, do: "current"
end
