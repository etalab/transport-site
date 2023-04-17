defmodule Transport.Validators.GTFSRT do
  @moduledoc """
  Validate a GTFS-RT with gtfs-realtime-validato (https://github.com/MobilityData/gtfs-realtime-validator/)
  """
  import Ecto.Query
  alias DB.{Dataset, MultiValidation, Repo, Resource, ResourceHistory, ResourceMetadata}
  alias Transport.Validators.GTFSRT
  alias Transport.Validators.GTFSTransport
  require Logger

  @behaviour Transport.Validators.Validator

  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"
  @max_errors_per_section 5

  @impl Transport.Validators.Validator
  def validator_name, do: "gtfs-realtime-validator"

  @impl Transport.Validators.Validator
  def validate_and_save(%Dataset{} = dataset), do: run_validate_and_save(dataset)
  def validate_and_save(%Resource{format: "gtfs-rt"} = resource), do: run_validate_and_save(resource)

  defp run_validate_and_save(dataset_or_resource) do
    resources = gtfs_rt_resources(dataset_or_resource)

    try do
      resources
      |> snapshot_gtfs_rts()
      |> Enum.reject(&(elem(&1, 2) == :error))
      |> Enum.each(fn snapshot ->
        {gtfs_resource, rt_resource, {:ok, gtfs_rt_path, cellar_filename}} = snapshot

        gtfs_path = download_path(gtfs_resource)
        gtfs_resource_history = gtfs_resource.resource_history |> Enum.at(0)
        download_latest_gtfs(gtfs_resource_history, gtfs_path)

        _validator_return =
          with {:ok, _} <- GTFSRT.run_validator(gtfs_path, gtfs_rt_path),
               {:ok, report} <- rt_resource |> gtfs_rt_result_path() |> GTFSRT.convert_validator_report() do
            insert_multi_validation(
              rt_resource,
              GTFSRT.build_validation_details(gtfs_resource_history, report, cellar_filename),
              gtfs_path,
              gtfs_rt_path,
              gtfs_resource,
              gtfs_resource_history
            )
          else
            :error -> {:error, "Could not run validator. Please provide a GTFS and a GTFS-RT."}
            e -> e
          end

        # add a validation log when the table is created
        # https://github.com/etalab/transport-site/issues/2390
        # log_validation(validator_return, resource)
      end)
    after
      Logger.debug("Cleaning up temporary files")
      Enum.each(resources, fn tuple -> tuple |> Tuple.to_list() |> Enum.each(&delete_tmp_files/1) end)
    end

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
    # See https://github.com/MobilityData/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#batch-processing

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
        %ResourceHistory{payload: %{"uuid" => uuid, "permanent_url" => permanent_url, "format" => "GTFS"}},
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

  def up_to_date_gtfs_resources(%Resource{dataset_id: dataset_id}),
    do: up_to_date_gtfs_resources(%Dataset{id: dataset_id})

  def up_to_date_gtfs_resources(%Dataset{id: dataset_id}) do
    Resource.base_query()
    |> ResourceHistory.join_resource_with_latest_resource_history()
    |> MultiValidation.join_resource_history_with_latest_validation(GTFSTransport.validator_name())
    |> ResourceMetadata.join_validation_with_metadata()
    |> where([resource: r], r.format == "GTFS" and r.dataset_id == ^dataset_id)
    |> ResourceMetadata.where_gtfs_up_to_date()
    |> preload([resource_history: rh], resource_history: rh)
    |> Repo.all()
  end

  def gtfs_rt_resources(%Resource{id: resource_id, dataset_id: dataset_id}) do
    %Dataset{id: dataset_id}
    |> gtfs_rt_resources()
    |> Enum.filter(fn {_gtfs, %Resource{id: id, format: "gtfs-rt"}} -> id == resource_id end)
  end

  @spec gtfs_rt_resources(Dataset.t() | Resource.t()) :: [] | [{Resource.t(), Resource.t()}]
  @doc """
  Identifies couples of {GTFS, GTFS-RT} resources to run GTFS-RT validation on.

  Resources in scope:
  - up-to-date GTFS in the dataset
  - GTFS-RT currently available in the dataset

  Based on the number of up-to-date GTFS resources, we can determine the relevant GTFS
  to use to perform GTFS-RT validation:
  - 0 GTFS: nothing to do
  - 1 up-to-date GTFS: we will use this resource to perform validation, **regardless** of
  potential related resources
  - at least 2 up-to-date GTFS: use `DB.ResourceRelated` with the reason `:gtfs_rt_gtfs`
  to know the GTFS to use for each GTFS-RT. If a GTFS-RT does not have a related resource,
  it will not be validated.
  """
  def gtfs_rt_resources(%Dataset{id: dataset_id} = dataset) do
    gtfs_resources = up_to_date_gtfs_resources(dataset)

    gtfs_rt_resources =
      Resource.base_query()
      |> preload([:resources_related])
      |> where([resource: r], r.format == "gtfs-rt" and r.is_available and r.dataset_id == ^dataset_id)
      |> Repo.all()

    case Enum.count(gtfs_resources) do
      0 ->
        []

      1 ->
        Enum.into(gtfs_rt_resources, [], fn %Resource{format: "gtfs-rt"} = resource ->
          {hd(gtfs_resources), resource}
        end)

      n when n > 1 ->
        gtfs_rt_and_gtfs_resources(gtfs_rt_resources, gtfs_resources)
    end
  end

  @spec gtfs_rt_and_gtfs_resources([Resource.t()], [Resource.t()]) :: [{Resource.t(), Resource.t()}] | []
  defp gtfs_rt_and_gtfs_resources(gtfs_rt_resources, gtfs_resources) do
    gtfs_rt_resources
    |> Enum.map(fn %Resource{format: "gtfs-rt"} = resource ->
      case Enum.find(resource.resources_related, &match?(%DB.ResourceRelated{reason: :gtfs_rt_gtfs}, &1)) do
        %DB.ResourceRelated{reason: :gtfs_rt_gtfs, resource_dst_id: gtfs_id} ->
          {Enum.find(gtfs_resources, fn %Resource{format: "GTFS", id: id} -> id == gtfs_id end), resource}

        nil ->
          {nil, resource}
      end
    end)
    |> Enum.reject(&match?({nil, %Resource{format: "gtfs-rt"}}, &1))
  end

  defp insert_multi_validation(
         %Resource{format: "gtfs-rt"} = gtfs_rt_resource,
         %{} = validation_details,
         gtfs_path,
         gtfs_rt_path,
         %Resource{format: "GTFS"} = gtfs_resource,
         %ResourceHistory{} = gtfs_resource_history
       ) do
    %MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      command: command(gtfs_path, gtfs_rt_path),
      result: validation_details,
      resource_id: gtfs_rt_resource.id,
      secondary_resource_id: gtfs_resource.id,
      secondary_resource_history_id: gtfs_resource_history.id,
      max_error: Map.fetch!(validation_details, "max_severity")
    }
    |> Repo.insert!()
  end

  defp delete_tmp_files(%Resource{format: "GTFS"} = resource) do
    resource |> download_path() |> remove_file()
    resource |> download_path() |> Path.dirname() |> File.rmdir()
  end

  defp delete_tmp_files(%Resource{format: "gtfs-rt"} = resource) do
    # Clean GTFS-RT: binaries, validation results and folders
    resource |> download_path() |> remove_file()
    resource |> gtfs_rt_result_path() |> remove_file()
    resource |> download_path() |> Path.dirname() |> File.rmdir()
  end

  defp snapshot_gtfs_rts(resources) do
    Enum.map(resources, fn {%Resource{format: "GTFS"} = gtfs_resource, %Resource{format: "gtfs-rt"} = gtfs_rt_resource} ->
      {gtfs_resource, gtfs_rt_resource, snapshot_gtfs_rt(gtfs_rt_resource)}
    end)
  end

  defp snapshot_gtfs_rt(%Resource{format: "gtfs-rt"} = resource) do
    resource |> download_resource(download_path(resource)) |> process_download(resource)
  end

  defp upload_filename(%Resource{id: resource_id, format: format}, %DateTime{} = dt) when format == "gtfs-rt" do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{resource_id}/#{resource_id}.#{time}.bin"
  end

  defp download_latest_gtfs(%ResourceHistory{payload: %{"permanent_url" => url, "format" => "GTFS"}}, tmp_path) do
    unless File.exists?(tmp_path) do
      %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)
      File.write!(tmp_path, body)
    end
  end

  defp download_resource(%Resource{id: resource_id, url: url, is_available: true, format: "gtfs-rt"}, tmp_path) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("Saving resource #{resource_id} to #{tmp_path}")
        File.write!(tmp_path, body)
        {:ok, tmp_path, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "Got a non 200 status: #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Got an error: #{reason}"}
    end
  end

  defp process_download({:error, message}, %Resource{id: resource_id}) do
    Logger.debug("Got an error while downloading #{resource_id}: #{message}")
    :error
  end

  defp process_download({:ok, tmp_path, body}, %Resource{} = resource) do
    cellar_filename = upload_filename(resource, DateTime.utc_now())
    Transport.S3.upload_to_s3!(:history, body, cellar_filename)
    {:ok, tmp_path, cellar_filename}
  end

  def download_path(%Resource{id: resource_id}) do
    resource_id = resource_id |> to_string()
    folder = System.tmp_dir!() |> Path.join("resource_#{resource_id}_gtfs_rt_multi_validation")
    File.mkdir_p!(folder)
    Path.join([folder, resource_id])
  end

  def gtfs_rt_result_path(%Resource{format: format} = resource) when format == "gtfs-rt" do
    # https://github.com/MobilityData/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#output
    "#{download_path(resource)}.results.json"
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
  defp remove_file(path), do: File.rm(path)
end
