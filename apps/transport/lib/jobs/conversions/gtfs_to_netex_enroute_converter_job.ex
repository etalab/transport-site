defmodule Transport.Jobs.GTFSToNeTExEnRouteConverterJob do
  @moduledoc """
  This Oban job is in charge of:
  - action=create: creating a `DB.DataConversion` and asking EnRoute to convert a GTFS to NeTEx
  - action=poll: polling the EnRoute's API to know if the conversion is still ongoing, done or failed
  - action=download: downloading a conversion that is finished, saving it in our S3 and updating our database.
  """
  use Oban.Worker,
    queue: :enroute_conversions,
    # This is *not* the maximum number of polling attempts, it is the maximum number
    # of attempts per (job, args).
    # The polling attempt number is present in the args.
    max_attempts: 3,
    tags: ["conversions"],
    unique: [period: :infinity, fields: [:args, :queue, :worker]]

  alias Transport.Converters.GTFSToNeTExEnRoute
  import Ecto.Query

  # The maximum number of polling attempts before a timeout
  # 720 attempts, waiting 30s between attempts = 6 hours.
  # See `next_polling_attempt_seconds/1`
  @max_attempts 720

  @impl true
  # Creating a conversion through the API and saving it in the database
  def perform(%Oban.Job{args: %{"action" => "create", "resource_history_id" => resource_history_id}}) do
    %DB.ResourceHistory{payload: %{"permanent_url" => permanent_url, "uuid" => rh_uuid}} =
      resource_history = DB.Repo.get!(DB.ResourceHistory, resource_history_id)

    if conversion_exists?(resource_history) do
      {:discard, "An #{converter()} conversion already exists for ResourceHistory##{resource_history_id}"}
    else
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
        |> __MODULE__.new(schedule_in: 15)
        |> Oban.insert!()

        :ok
      after
        File.rm(tmp_filepath)
      end
    end
  end

  @impl true
  # Polling when attempt = max_attempts
  def perform(%Oban.Job{
        args: %{"action" => "poll", "data_conversion_id" => data_conversion_id, "attempt" => attempt}
      })
      when attempt == @max_attempts do
    DB.DataConversion
    |> DB.Repo.get!(data_conversion_id)
    |> update_data_conversion!({:timeout, %{"stopped_at" => DateTime.utc_now()}}, attempt)

    :ok
  end

  @impl true
  # Polling, general case
  def perform(%Oban.Job{
        args: %{"action" => "poll", "data_conversion_id" => data_conversion_id, "attempt" => attempt} = job_args
      }) do
    %DB.DataConversion{status: status, payload: %{"converter" => %{"id" => conversion_id}}} =
      data_conversion = DB.Repo.get!(DB.DataConversion, data_conversion_id)

    if status in [:created, :pending] do
      case GTFSToNeTExEnRoute.get_conversion(conversion_id) do
        {:pending, %{}} = return ->
          update_data_conversion!(data_conversion, return, attempt)

          %{job_args | "attempt" => attempt + 1}
          |> __MODULE__.new(schedule_in: next_polling_attempt_seconds(attempt))
          |> Oban.insert!()

        {:success, %{} = metadata} ->
          # Switching to `status=success` should be done when downloading the file
          update_data_conversion!(data_conversion, {:pending, metadata}, attempt)

          %{"action" => "download", "data_conversion_id" => data_conversion_id}
          |> __MODULE__.new()
          |> Oban.insert!()

        {:failed, %{}} = return ->
          update_data_conversion!(data_conversion, return, attempt)
      end

      :ok
    else
      {:discard,
       "Unexpected status for DataConversion##{data_conversion_id}. It should be created or pending. #{inspect(data_conversion)}"}
    end
  end

  @impl true
  # Downloading a conversion that is finished
  def perform(%Oban.Job{args: %{"action" => "download", "data_conversion_id" => data_conversion_id}}) do
    %DB.DataConversion{
      status: :pending,
      resource_history_uuid: rh_uuid,
      payload: %{"converter" => %{"id" => conversion_id} = payload}
    } =
      data_conversion = DB.Repo.get!(DB.DataConversion, data_conversion_id)

    conversion_filename = "#{rh_uuid}.netex.zip"
    conversion_filepath = System.tmp_dir!() |> Path.join(conversion_filename)
    s3_filepath = "conversions/gtfs-to-netex/#{conversion_filename}"

    try do
      GTFSToNeTExEnRoute.download_conversion(conversion_id, File.stream!(conversion_filepath))
      %File.Stat{size: filesize} = File.stat!(conversion_filepath)

      Transport.S3.stream_to_s3!(:history, conversion_filepath, s3_filepath, acl: :public_read)

      data_conversion
      |> Ecto.Changeset.change(%{
        status: :success,
        payload:
          Map.merge(payload, %{
            filename: s3_filepath,
            permanent_url: Transport.S3.permanent_url(:history, s3_filepath),
            filesize: filesize
          })
      })
      |> DB.Repo.update!()

      :ok
    after
      File.rm(conversion_filepath)
    end
  end

  @spec update_data_conversion!(DB.DataConversion.t(), {atom(), map()}, pos_integer()) :: DB.DataConversion.t()
  defp update_data_conversion!(
         %DB.DataConversion{payload: %{"converter" => %{"id" => conversion_id}} = payload} = data_conversion,
         {status, %{} = converter_result},
         attempt
       ) do
    converter_payload = Map.merge(converter_result, %{"id" => conversion_id, "attempt" => attempt})

    data_conversion
    |> Ecto.Changeset.change(%{payload: %{payload | "converter" => converter_payload}, status: status})
    |> DB.Repo.update!()
  end

  @doc """
  How many seconds should we wait before polling again?
  Poll every 10s during the first 2 minutes and then wait for 30 seconds.

  iex> next_polling_attempt_seconds(1)
  10
  iex> next_polling_attempt_seconds(15)
  30
  iex> next_polling_attempt_seconds(500)
  30
  """
  def next_polling_attempt_seconds(current_attempt) when current_attempt < 12, do: 10

  def next_polling_attempt_seconds(current_attempt) when current_attempt >= 13 and current_attempt < @max_attempts,
    do: 30

  def conversion_exists?(%DB.ResourceHistory{payload: %{"uuid" => rh_uuid}}) do
    converter = converter()

    DB.DataConversion.base_query()
    |> where(
      [data_conversion: dc],
      dc.resource_history_uuid == ^rh_uuid and dc.convert_from == :GTFS and dc.convert_to == :NeTEx and
        dc.converter == ^converter
    )
    |> DB.Repo.exists?()
  end

  def tmp_path(%DB.ResourceHistory{id: id}) do
    System.tmp_dir!() |> Path.join("enroute_conversion_gtfs_netex_#{id}}")
  end

  def converter, do: "enroute/gtfs-to-netex"

  @doc """
  The EnRoute converter version. Not available yet.
  https://enroute.atlassian.net/servicedesk/customer/portal/1/SUPPORT-1091
  """
  def converter_version, do: "current"
end
