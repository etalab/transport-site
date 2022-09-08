defmodule Transport.Validators.GTFSRT do
  @moduledoc """
  Validate a GTFS-RT with gtfs-realtime-validato (https://github.com/CUTR-at-USF/gtfs-realtime-validator/)
  """
  @behaviour Transport.Validators.Validator

  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"
  @max_errors_per_section 5

  @impl Transport.Validators.Validator
  def validator_name, do: "gtfs-realtime-validator"

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.Resource{id: resource_id, dataset_id: dataset_id, format: "gtfs-rt"}) do
    %{"dataset_id" => dataset_id, "resource_id" => resource_id}
    |> Transport.Jobs.GTFSRTMultiValidationJob.new()
    |> Oban.insert!()

    :ok
  end

  defp validator_arguments(gtfs_path, gtfs_rt_path) do
    binary_path = "java"

    args = [
      "-jar",
      Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename),
      "-gtfs",
      gtfs_path,
      "-gtfsRealtimePath",
      Path.dirname(gtfs_rt_path)
    ]

    {binary_path, args}
  end

  def command(gtfs_path, gtfs_rt_path), do: inspect(validator_arguments(gtfs_path, gtfs_rt_path))

  def run_validator(gtfs_path, gtfs_rt_path) do
    # See https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#batch-processing

    {binary_path, args} = validator_arguments(gtfs_path, gtfs_rt_path)

    Transport.RamboLauncher.run(binary_path, args, log: Mix.env() == :dev)
  end

  @spec convert_validator_report(binary()) :: {:ok, map()} | :error
  def convert_validator_report(path) do
    case File.read(path) do
      {:ok, content} ->
        errors =
          content
          |> Jason.decode!()
          |> Enum.map(fn error ->
            rule = Map.fetch!(Map.fetch!(error, "errorMessage"), "validationRule")
            suffix = Map.fetch!(rule, "occurrenceSuffix")
            occurence_list = Map.fetch!(error, "occurrenceList")

            %{
              "error_id" => Map.fetch!(rule, "errorId"),
              "severity" => Map.fetch!(rule, "severity"),
              "title" => Map.fetch!(rule, "title"),
              "description" => Map.fetch!(rule, "errorDescription"),
              "errors_count" => Enum.count(occurence_list),
              "errors" =>
                occurence_list
                |> Enum.take(@max_errors_per_section)
                |> Enum.map(&"#{Map.fetch!(&1, "prefix")} #{suffix}")
            }
          end)

        total_errors =
          errors
          |> Enum.filter(&(Map.fetch!(&1, "severity") == "ERROR"))
          |> Enum.map(&Map.fetch!(&1, "errors_count"))
          |> Enum.sum()

        total_warnings =
          errors
          |> Enum.filter(&(Map.fetch!(&1, "severity") == "WARNING"))
          |> Enum.map(&Map.fetch!(&1, "errors_count"))
          |> Enum.sum()

        {:ok,
         %{
           "errors_count" => total_errors,
           "warnings_count" => total_warnings,
           "has_errors" => total_errors + total_warnings > 0,
           "errors" => errors
         }}

      {:error, _} ->
        :error
    end
  end

  def get_max_severity_error(%{"errors" => errors}), do: get_max_severity_error(errors)

  def get_max_severity_error([]), do: nil

  def get_max_severity_error(errors) do
    severities = errors |> Enum.map(&Map.fetch!(&1, "severity")) |> MapSet.new()

    unless MapSet.subset?(severities, MapSet.new(["WARNING", "ERROR"])) do
      raise "Some severity levels are not handled #{inspect(severities)}"
    end

    cond do
      "ERROR" in severities -> "ERROR"
      "WARNING" in severities -> "WARNING"
    end
  end

  def build_validation_details(
        %DB.ResourceHistory{payload: %{"uuid" => uuid, "permanent_url" => permanent_url, "format" => "GTFS"}},
        %{"has_errors" => _, "errors" => _, "errors_count" => _, "warnings_count" => _} = validation_report,
        gtfs_rt_cellar_filename
      ) do
    Map.merge(validation_report, %{
      "max_severity" => get_max_severity_error(validation_report),
      "files" => %{
        "gtfs_resource_history_uuid" => uuid,
        "gtfs_permanent_url" => permanent_url,
        "gtfs_rt_filename" => gtfs_rt_cellar_filename,
        "gtfs_rt_permanent_url" => Transport.S3.permanent_url(:history, gtfs_rt_cellar_filename)
      },
      "uuid" => Ecto.UUID.generate()
    })
  end
end
