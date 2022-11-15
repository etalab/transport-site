defmodule Transport.Jobs.GTFSGenericConverter do
  @moduledoc """
  Provides some functions to convert GTFS to another format
  """
  alias DB.{DataConversion, Repo, ResourceHistory}
  import Ecto.Query
  require Logger

  @allowed_formats ["GeoJSON", "NeTEx"]

  @doc """
  Enqueues conversion jobs for all resource history that need one.
  """
  @spec enqueue_all_conversion_jobs(binary(), module()) :: :ok
  def enqueue_all_conversion_jobs(format, conversion_job_module) when format in @allowed_formats do
    fatal_error_key = fatal_error_key(format)

    query =
      ResourceHistory
      |> where(
        [_r],
        fragment(
          """
          payload ->>'format'='GTFS'
          AND NOT payload \\? ?
          AND
          payload ->>'uuid' NOT IN
          (SELECT resource_history_uuid::text FROM data_conversion WHERE convert_from='GTFS' and convert_to=?)
          """,
          ^fatal_error_key,
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

  defp fatal_error_key(format) when format in @allowed_formats, do: "conversion_#{format}_fatal_error"

  defp is_resource_gtfs?(%{payload: %{"format" => "GTFS"}}), do: true

  defp is_resource_gtfs?(_), do: false

  @spec format_exists?(any(), binary()) :: boolean
  defp format_exists?(%{payload: %{"uuid" => resource_uuid}}, format) when format in @allowed_formats do
    DataConversion
    |> Repo.get_by(convert_from: "GTFS", convert_to: format, resource_history_uuid: resource_uuid) !== nil
  end

  defp format_exists?(_, _), do: false

  @doc """
  Converts a resource_history to the targeted format, using a converter module
  """
  @spec perform_single_conversion_job(integer(), binary(), module()) :: :ok
  def perform_single_conversion_job(resource_history_id, format, converter_module) when format in @allowed_formats do
    resource_history = ResourceHistory |> Repo.get(resource_history_id)

    case is_resource_gtfs?(resource_history) and not format_exists?(resource_history, format) do
      true ->
        generate_and_upload_conversion(resource_history, format, converter_module)

      false ->
        Logger.info("Skipping #{format} conversion of resource history #{resource_history_id}")
        {:discard, "Conversion is not needed"}
    end
  end

  defp generate_and_upload_conversion(
         %ResourceHistory{
           id: resource_history_id,
           resource_id: resource_id,
           datagouv_id: resource_datagouv_id,
           payload: %{"uuid" => resource_uuid, "permanent_url" => resource_url, "filename" => resource_filename}
         } = resource_history,
         format,
         converter_module
       )
       when format in @allowed_formats do
    format_lower = format |> String.downcase()
    Logger.info("Starting conversion of download uuid #{resource_uuid}, from GTFS to #{format}")

    gtfs_file_path =
      System.tmp_dir!()
      |> Path.join("conversion_gtfs_#{format_lower}_#{resource_history_id}_#{:os.system_time(:millisecond)}")

    conversion_output_path = "#{gtfs_file_path}.#{format_lower}"
    zip_path = "#{conversion_output_path}.zip"

    try do
      %{status_code: 200, body: body} = Transport.Shared.Wrapper.HTTPoison.impl().get!(resource_url)

      File.write!(gtfs_file_path, body)

      case converter_module.convert(gtfs_file_path, conversion_output_path) do
        :ok ->
          # gtfs2netex converter outputs a folder, we need to zip it
          zip_conversion? = File.dir?(conversion_output_path)

          file =
            zip_conversion?
            |> case do
              true ->
                :ok = Transport.FolderZipper.zip(conversion_output_path, zip_path)
                zip_path

              false ->
                conversion_output_path
            end
            |> File.read!()

          conversion_file_name =
            resource_filename |> conversion_file_name(format_lower) |> add_zip_extension(zip_conversion?)

          Transport.S3.upload_to_s3!(:history, file, conversion_file_name)

          {:ok, %{size: filesize}} = File.stat(conversion_output_path)

          %DataConversion{
            convert_from: "GTFS",
            convert_to: format,
            resource_history_uuid: resource_uuid,
            payload: %{
              filename: conversion_file_name,
              permanent_url: Transport.S3.permanent_url(:history, conversion_file_name),
              resource_id: resource_id,
              resource_datagouv_id: resource_datagouv_id,
              filesize: filesize
            }
          }
          |> Repo.insert!()

          :ok

        {:error, reason} ->
          resource_history
          |> Ecto.Changeset.change(%{
            payload:
              Map.merge(resource_history.payload, %{
                fatal_error_key(format) => true,
                "conversion_#{format}_error" => reason
              })
          })
          |> Repo.update!()

          {:discard, "Converter returned an error: #{reason}"}
      end
    after
      File.rm(gtfs_file_path)
      File.rm_rf(conversion_output_path)
      # may not exist
      File.rm(zip_path)
    end
  end

  defp conversion_file_name(resource_name, format), do: "conversions/gtfs-to-#{format}/#{resource_name}.#{format}"

  defp add_zip_extension(path, true = _zip_conversion?), do: "#{path}.zip"
  defp add_zip_extension(path, _), do: path
end

defmodule Transport.FolderZipper do
  @moduledoc """
  Zip a folder using the zip external command
  """
  def zip(folder_path, zip_name) do
    case Transport.RamboLauncher.run("zip", [zip_name, "-r", "./"], cd: folder_path) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, e}
    end
  end
end
