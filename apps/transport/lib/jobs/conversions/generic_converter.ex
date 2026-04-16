defmodule Transport.Jobs.GenericConverter do
  @moduledoc """
  Provides some functions to convert GTFS to another format.

  Note that the EnRoute's GTFS to NeTEx converter does not use this class
  because the conversion is not done locally but through an API.
  """
  alias DB.{DataConversion, Repo, ResourceHistory}
  import Ecto.Query
  require Logger

  @allowed_formats ["GeoJSON"]

  def enqueue_all_conversion_jobs(source_format, target_format, conversion_job_module) do
    fatal_error_key = fatal_error_key(target_format)
    converter = conversion_job_module.converter()

    query =
      ResourceHistory
      |> where(
        [_r],
        fragment(
          """
          payload ->>'format'=?
          AND NOT payload \\? ?
          AND
          payload ->>'uuid' NOT IN
          (SELECT resource_history_uuid::text FROM data_conversion WHERE convert_from=? and convert_to=? and converter=?)
          """,
          ^source_format,
          ^fatal_error_key,
          ^source_format,
          ^target_format,
          ^converter
        )
      )
      |> select([r], r.id)

    stream = Repo.stream(query)

    Repo.transaction(fn ->
      stream
      |> Stream.each(fn id ->
        %{"resource_history_id" => id, "action" => "create"}
        |> conversion_job_module.new()
        |> Oban.insert()
      end)
      |> Stream.run()
    end)

    :ok
  end

  defp fatal_error_key(format) when format in @allowed_formats, do: "conversion_#{format}_fatal_error"

  defp resource_of_format?(expected_format, %{payload: %{"format" => format}}), do: to_string(expected_format) == format
  defp resource_of_format?(_, _), do: false

  @spec conversion_exists?(DB.ResourceHistory.t() | nil, binary(), binary(), module()) :: boolean
  @doc """
  Checks if a conversion already exists for a `DB.ResourceHistory` and a target format.
  """
  def conversion_exists?(
        %DB.ResourceHistory{payload: %{"uuid" => resource_uuid}},
        source_format,
        target_format,
        converter_module
      )
      when target_format in @allowed_formats do
    DataConversion
    |> Repo.get_by(
      convert_from: source_format,
      convert_to: target_format,
      converter: converter_module.converter(),
      resource_history_uuid: resource_uuid
    ) !== nil
  end

  def conversion_exists?(nil, _, _, _), do: false

  @doc """
  Converts a resource_history to the targeted format, using a converter module
  """
  @spec perform_single_conversion_job(integer(), binary(), binary(), module()) :: :ok
  def perform_single_conversion_job(resource_history_id, source_format, target_format, converter_module)
      when target_format in @allowed_formats do
    resource_history = ResourceHistory |> Repo.get(resource_history_id)

    case resource_of_format?(source_format, resource_history) and
           not conversion_exists?(resource_history, source_format, target_format, converter_module) do
      true ->
        generate_and_upload_conversion(resource_history, source_format, target_format, converter_module)

      false ->
        Logger.info("Skipping #{target_format} conversion of resource history #{resource_history_id}")
        {:cancel, "Conversion is not needed"}
    end
  end

  defp generate_and_upload_conversion(
         %ResourceHistory{
           id: resource_history_id,
           resource_id: resource_id,
           datagouv_id: resource_datagouv_id,
           payload: %{"uuid" => resource_uuid, "permanent_url" => resource_url, "filename" => resource_filename}
         } = resource_history,
         source_format,
         target_format,
         converter_module
       )
       when target_format in @allowed_formats do
    source_format_lower = source_format |> to_string() |> String.downcase()
    target_format_lower = target_format |> String.downcase()
    Logger.info("Starting conversion of download uuid #{resource_uuid}, from #{source_format} to #{target_format}")

    source_file_path =
      System.tmp_dir!()
      |> Path.join(
        "conversion_#{source_format_lower}_#{target_format_lower}_#{resource_history_id}_#{:os.system_time(:millisecond)}"
      )

    conversion_output_path = "#{source_file_path}.#{target_format_lower}"
    zip_path = "#{conversion_output_path}.zip"

    try do
      %{status_code: 200, body: body} = Transport.Shared.Wrapper.HTTPoison.impl().get!(resource_url)

      File.write!(source_file_path, body)

      case converter_module.convert(source_file_path, conversion_output_path) do
        :ok ->
          # gtfs2netex converter outputs a folder, we need to zip it
          zip_conversion? = File.dir?(conversion_output_path)

          path =
            if zip_conversion? do
              :ok = Transport.FolderZipper.zip(conversion_output_path, zip_path)
              zip_path
            else
              conversion_output_path
            end

          %File.Stat{size: filesize} = File.stat!(path)

          conversion_file_name =
            resource_filename
            |> conversion_file_name(source_format_lower, target_format_lower)
            |> add_zip_extension(zip_conversion?)

          Transport.S3.stream_to_s3!(:history, path, conversion_file_name, acl: :public_read)

          %DataConversion{
            convert_from: source_format,
            convert_to: String.to_existing_atom(target_format),
            status: :success,
            converter: converter_module.converter(),
            converter_version: converter_module.converter_version(),
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
                fatal_error_key(target_format) => true,
                "conversion_#{target_format}_error" => reason
              })
          })
          |> Repo.update!()

          {:cancel, "Converter returned an error: #{reason}"}
      end
    after
      File.rm(source_file_path)
      File.rm_rf(conversion_output_path)
      # may not exist
      File.rm(zip_path)
    end
  end

  defp conversion_file_name(resource_name, source_format, target_format),
    do: "conversions/#{source_format}-to-#{target_format}/#{resource_name}.#{target_format}"

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
