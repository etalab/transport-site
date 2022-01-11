defmodule Transport.Jobs.GTFSGenericConverter do
  @moduledoc """
  Provides some functions to convert GTFS to another format
  """
  alias DB.{DataConversion, Repo, ResourceHistory}
  import Ecto.Query
  require Logger

  @doc """
  Enqueues conversion jobs for all resource history that need one.
  """
  @spec enqueue_all_conversion_jobs(binary(), module()) :: :ok
  def enqueue_all_conversion_jobs(format, conversion_job_module) when format in ["GeoJSON", "NeTEx"] do
    query =
      ResourceHistory
      |> where(
        [_r],
        fragment(
          """
          payload ->>'format'='GTFS'
          AND
          payload ->>'uuid' NOT IN
          (SELECT resource_history_uuid::text FROM data_conversion WHERE convert_from='GTFS' and convert_to=?)
          """,
          ^format
        )
      )
      |> select([r], r.id)

    stream = Repo.stream(query)

    Repo.transaction(fn ->
      stream
      |> Stream.each(fn id ->
        %{"resource_history_id" => id}
        |> conversion_job_module.new()
        |> Oban.insert()
      end)
      |> Stream.run()
    end)

    :ok
  end

  defp is_resource_gtfs?(%{payload: %{"format" => "GTFS"}}), do: true

  defp is_resource_gtfs?(_), do: false

  @spec format_exists?(any(), binary()) :: boolean
  defp format_exists?(%{payload: %{"uuid" => resource_uuid}}, format) do
    DataConversion
    |> Repo.get_by(convert_from: "GTFS", convert_to: format, resource_history_uuid: resource_uuid) !== nil
  end

  defp format_exists?(_, _), do: false

  @doc """
  Converts a resource_history to the targeted format, using a converter module
  """
  @spec perform_single_conversion_job(integer(), binary(), module()) :: :ok
  def perform_single_conversion_job(resource_history_id, format, converter_module) do
    resource_history = ResourceHistory |> Repo.get(resource_history_id)

    if is_resource_gtfs?(resource_history) and not format_exists?(resource_history, format) do
      generate_and_upload_conversion(resource_history, format, converter_module)
    end

    :ok
  end

  defp generate_and_upload_conversion(
         %{
           id: resource_history_id,
           datagouv_id: resource_datagouv_id,
           payload: %{"uuid" => resource_uuid, "permanent_url" => resource_url, "filename" => resource_filename}
         },
         format,
         converter_module
       ) do
    format_lower = format |> String.downcase()
    Logger.info("Starting conversion of download uuid #{resource_uuid}, from GTFS to #{format}")

    gtfs_file_path =
      System.tmp_dir!()
      |> Path.join("conversion_gtfs_#{format_lower}_#{resource_history_id}_#{:os.system_time(:millisecond)}")

    conversion_file_path = "#{gtfs_file_path}.#{format_lower}"

    try do
      %{status_code: 200, body: body} = Transport.Shared.Wrapper.HTTPoison.impl().get!(resource_url)

      File.write!(gtfs_file_path, body)

      :ok = apply(converter_module, :convert, [gtfs_file_path, conversion_file_path])
      file = conversion_file_path |> File.read!()

      conversion_file_name = resource_filename |> conversion_file_name(format_lower)
      Transport.S3.upload_to_s3!(:history, file, conversion_file_name)

      {:ok, %{size: filesize}} = File.stat(conversion_file_path)

      %DataConversion{
        convert_from: "GTFS",
        convert_to: format,
        resource_history_uuid: resource_uuid,
        payload: %{
          filename: conversion_file_name,
          permanent_url: Transport.S3.permanent_url(:history, conversion_file_name),
          resource_datagouv_id: resource_datagouv_id,
          filesize: filesize
        }
      }
      |> Repo.insert!()
    after
      File.rm(gtfs_file_path)
      File.rm(conversion_file_path)
    end
  end

  defp conversion_file_name(resource_name, format), do: "conversions/gtfs-to-#{format}/#{resource_name}.#{format}"
end
