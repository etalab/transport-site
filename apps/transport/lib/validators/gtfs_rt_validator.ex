defmodule Transport.Validators.GTFSRT do
  @moduledoc """
  Validate a GTFS-RT with gtfs-realtime-validato (https://github.com/MobilityData/gtfs-realtime-validator/)
  """
  import Ecto.Query
  alias DB.{Dataset, MultiValidation, Repo, Resource, ResourceHistory, ResourceMetadata}
  alias Transport.Validators.GTFSRT
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
      |> Enum.each(fn snapshot -> run_validator_and_save(snapshot) end)
    after
      Logger.debug("Cleaning up temporary files")
      Enum.each(resources, fn tuple -> tuple |> Tuple.to_list() |> Enum.each(&delete_tmp_files/1) end)
    end

    :ok
  end

  defp run_validator_and_save({gtfs_resource, rt_resource, {:ok, gtfs_rt_path, cellar_filename}} = snapshot, opts \\ []) do
    opts = Keyword.validate!(opts, ignore_shapes: false)
    ignore_shapes = Keyword.fetch!(opts, :ignore_shapes)
    gtfs_path = download_path(gtfs_resource)
    gtfs_resource_history = gtfs_resource.resource_history |> Enum.at(0)
    download_latest_gtfs(gtfs_resource_history, gtfs_path)
    validator_args = validator_arguments(gtfs_path, gtfs_rt_path, opts)

    with {:ok, _} <- GTFSRT.run_validator(validator_args),
         {:ok, report} <- rt_resource |> gtfs_rt_result_path() |> GTFSRT.convert_validator_report(opts) do
      insert_multi_validation(
        rt_resource,
        GTFSRT.build_validation_details(gtfs_resource_history, report, cellar_filename),
        validator_args,
        gtfs_resource,
        gtfs_resource_history
      )
    else
      :error ->
        {:error, "Could not run validator. Please provide a GTFS and a GTFS-RT."}

      {:error, message} ->
        if not ignore_shapes and String.contains?(message, "java.lang.OutOfMemoryError") do
          run_validator_and_save(snapshot, ignore_shapes: true)
        end
    end
  end

  @spec validator_arguments(binary(), binary(), ignore_shapes: boolean()) :: {binary(), [binary()]}
  def validator_arguments(gtfs_path, gtfs_rt_path, opts \\ []) do
    binary_path = "java"
    opts = Keyword.validate!(opts, ignore_shapes: false)

    # Do not process shapes.txt: this requires a large amount of memory
    # https://github.com/MobilityData/gtfs-realtime-validator/blob/master/TROUBLESHOOTING.md#javalangoutofmemoryerror-java-heap-space-when-running-project
    shapes_args =
      if Keyword.fetch!(opts, :ignore_shapes) do
        ["-ignoreShapes", "yes"]
      else
        []
      end

    args =
      [
        "-jar",
        Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename),
        shapes_args,
        "-gtfs",
        gtfs_path,
        "-gtfsRealtimePath",
        Path.dirname(gtfs_rt_path)
      ]
      |> List.flatten()
      |> Enum.reject(&(&1 == ""))

    {binary_path, args}
  end

  def run_validator({binary_path, args}) do
    # See https://github.com/MobilityData/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#batch-processing
    Transport.RamboLauncher.run(binary_path, args, log: Mix.env() == :dev)
  end

  @spec convert_validator_report(binary(), ignore_shapes: boolean()) :: {:ok, map()} | :error
  def convert_validator_report(path, opts \\ []) do
    opts = Keyword.validate!(opts, ignore_shapes: false)

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
           "ignore_shapes" => Keyword.fetch!(opts, :ignore_shapes),
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
    |> MultiValidation.join_resource_history_with_latest_validation(
      Enum.map(Transport.ValidatorsSelection.validators_for_feature(:gtfs_rt_validator), & &1.validator_name())
    )
    |> ResourceMetadata.join_validation_with_metadata()
    |> where([resource: r], r.format == "GTFS" and not r.is_community_resource and r.dataset_id == ^dataset_id)
    |> ResourceMetadata.where_up_to_date()
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
      |> where(
        [resource: r],
        r.format == "gtfs-rt" and not r.is_community_resource and r.is_available and r.dataset_id == ^dataset_id
      )
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
         {_, _} = validator_arguments,
         %Resource{format: "GTFS"} = gtfs_resource,
         %ResourceHistory{} = gtfs_resource_history
       ) do
    %MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      command: inspect(validator_arguments),
      result: validation_details,
      digest: digest(validation_details),
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
    req_options = [compressed: false, decode_body: false, into: File.stream!(tmp_path)]

    unless File.exists?(tmp_path) do
      {:ok, %Req.Response{status: 200}} = Transport.Req.impl().get(url, req_options)
    end
  end

  defp download_resource(%Resource{id: resource_id, url: url, is_available: true, format: "gtfs-rt"}, tmp_path) do
    req_options = [compressed: false, decode_body: false, into: File.stream!(tmp_path)]

    case Transport.Req.impl().get(url, req_options) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.debug("Saving resource #{resource_id} to #{tmp_path}")
        {:ok, tmp_path}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Got a non 200 status: #{status}"}

      error ->
        {:error, "Got an error: #{inspect(error)}"}
    end
  end

  defp process_download({:error, message}, %Resource{id: resource_id}) do
    Logger.debug("Got an error while downloading #{resource_id}: #{message}")
    :error
  end

  defp process_download({:ok, tmp_path}, %Resource{} = resource) do
    cellar_filename = upload_filename(resource, DateTime.utc_now())
    Transport.S3.stream_to_s3!(:history, tmp_path, cellar_filename, acl: :public_read)
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

  defp remove_file(path), do: File.rm(path)

  @doc """
  iex> digest(%{"warnings_count" => 2, "errors_count" => 3, "issues" => []})
  %{"errors_count" => 3, "warnings_count" => 2}
  iex> digest(%{"issues" => []})
  %{}
  """
  @spec digest(map) :: map
  def digest(%{} = validation_result) do
    Map.intersect(%{"warnings_count" => 0, "errors_count" => 0}, validation_result)
  end
end
