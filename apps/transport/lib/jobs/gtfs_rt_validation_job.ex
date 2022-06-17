defmodule Transport.Jobs.GTFSRTValidationDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTValidationJob`.
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_datasets()
    |> Enum.map(&(%{dataset_id: &1.id} |> Transport.Jobs.GTFSRTValidationJob.new()))
    |> Oban.insert_all()

    :ok
  end

  def relevant_datasets do
    today = Date.utc_today()

    sub =
      Resource
      |> where([r], r.format == "GTFS" and r.is_available)
      |> where([r], r.start_date <= ^today and r.end_date >= ^today)
      |> select([r], r.dataset_id)
      |> group_by([r], r.dataset_id)
      |> having([r], count(r.id) == 1)

    Dataset
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], r.format == "gtfs-rt" and r.is_available)
    |> where([d, _r], d.is_active and d.id in subquery(sub))
    |> distinct(true)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTValidationJob do
  @moduledoc """
  Job validating gtfs-rt resources and saving validation
  results.
  """
  use Oban.Worker, max_attempts: 5, tags: ["validation"]
  import Ecto.{Changeset, Query}
  alias DB.{Dataset, LogsValidation, Repo, Resource, ResourceHistory, Validation}
  require Logger

  defguard is_gtfs_rt(format) when format in ["gtfs-rt", "gtfsrt"]

  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"
  @max_errors_per_section 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    dataset = Dataset |> preload([:resources, resources: [:validation]]) |> Repo.get!(dataset_id)

    gtfs = dataset.resources |> Enum.find(&(Resource.is_gtfs?(&1) and Resource.valid_and_available?(&1)))
    gtfs_rts = dataset.resources |> Enum.filter(&(Resource.is_gtfs_rt?(&1) and &1.is_available))

    if Enum.empty?(gtfs_rts) do
      raise "Should have gtfs-rt resources for Dataset #{dataset_id}"
    end

    gtfs_path = download_path(gtfs)
    gtfs_resource_history = latest_resource_history(gtfs)
    download_latest_gtfs(gtfs_resource_history, gtfs_path)

    try do
      gtfs_rts
      |> snapshot_gtfs_rts()
      |> Enum.reject(&(elem(&1, 1) == :error))
      |> Enum.each(fn snapshot ->
        {resource, {:ok, gtfs_rt_path, cellar_filename}} = snapshot

        validator_return =
          case run_validator(gtfs_path, gtfs_rt_path) do
            {:ok, _} = validator_return ->
              case convert_validator_report(gtfs_rt_result_path(resource)) do
                {:ok, report} ->
                  update_resource(resource, build_validation_details(gtfs_resource_history, report, cellar_filename))

                  validator_return

                :error ->
                  {:error, "Could not run validator. Please provide a GTFS and a GTFS-RT."}
              end

            {:error, _} = validator_return ->
              validator_return
          end

        log_validation(validator_return, resource)
      end)
    after
      Logger.debug("Cleaning up temporary files")
      clean_gtfs_rts(gtfs_rts)
      clean_gtfs(gtfs_path)
    end

    :ok
  end

  def run_validator(gtfs_path, gtfs_rt_path) do
    # See https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#batch-processing
    binary_path = "java"

    args = [
      "-jar",
      Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename),
      "-gtfs",
      gtfs_path,
      "-gtfsRealtimePath",
      Path.dirname(gtfs_rt_path)
    ]

    Transport.RamboLauncher.run(binary_path, args, log: Mix.env() == :dev)
  end

  defp update_resource(%Resource{} = resource, validation_details) do
    resource
    |> change(%{
      metadata: Map.merge(resource.metadata || %{}, %{"validation" => validation_details}),
      validation: %Validation{
        date: DateTime.utc_now() |> DateTime.to_string(),
        details: validation_details,
        max_error: Map.fetch!(validation_details, "max_severity")
      }
    })
    |> Repo.update!()
  end

  defp log_validation({:ok, _}, %Resource{id: id}) do
    %LogsValidation{
      resource_id: id,
      timestamp: DateTime.truncate(DateTime.utc_now(), :second),
      is_success: true
    }
    |> Repo.insert!()
  end

  defp log_validation({:error, message}, %Resource{id: id}) do
    error_message = "error while calling the validator: #{inspect(message)}"
    Logger.error(error_message)

    %LogsValidation{
      resource_id: id,
      timestamp: DateTime.truncate(DateTime.utc_now(), :second),
      is_success: false,
      error_msg: error_message
    }
    |> Repo.insert!()
  end

  defp clean_gtfs(gtfs_path) do
    remove_file(gtfs_path)
    File.rmdir(Path.dirname(gtfs_path))
  end

  defp clean_gtfs_rts(gtfs_rts) do
    # Clean GTFS-RT: binaries, validation results and folders
    gtfs_rts |> Enum.each(&(&1 |> download_path() |> remove_file()))
    gtfs_rts |> Enum.each(&(&1 |> gtfs_rt_result_path() |> remove_file()))
    gtfs_rts |> Enum.each(&(&1 |> download_path() |> Path.dirname() |> File.rmdir()))
  end

  defp build_validation_details(
         %ResourceHistory{payload: %{"uuid" => uuid, "permanent_url" => permanent_url, "format" => "GTFS"}},
         %{"has_errors" => _, "errors" => _, "errors_count" => _, "warnings_count" => _, "validator" => _} =
           validation_report,
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
      "uuid" => Ecto.UUID.generate(),
      "datetime" => DateTime.utc_now() |> DateTime.to_string()
    })
  end

  defp latest_resource_history(%Resource{id: resource_id, format: "GTFS"}) do
    ResourceHistory
    |> where([rh], rh.resource_id == ^resource_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  defp snapshot_gtfs_rts(gtfs_rts) do
    gtfs_rts |> Enum.map(&{&1, snapshot_gtfs_rt(&1)})
  end

  defp snapshot_gtfs_rt(%Resource{format: format} = resource) when is_gtfs_rt(format) do
    resource |> download_resource(download_path(resource)) |> process_download(resource)
  end

  defp upload_filename(%Resource{id: resource_id, format: format}, %DateTime{} = dt) when is_gtfs_rt(format) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{resource_id}/#{resource_id}.#{time}.bin"
  end

  defp download_latest_gtfs(%ResourceHistory{payload: %{"permanent_url" => url, "format" => "GTFS"}}, tmp_path) do
    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)
    File.write!(tmp_path, body)
  end

  defp download_resource(%Resource{id: resource_id, url: url, is_available: true, format: format}, tmp_path)
       when is_gtfs_rt(format) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("Saving resource##{resource_id} to #{tmp_path}")
        File.write!(tmp_path, body)
        {:ok, tmp_path, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "Got a non 200 status: #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Got an error: #{reason}"}
    end
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
           "errors" => errors,
           "validator" => __MODULE__ |> to_string
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

  defp process_download({:error, message}, %Resource{id: resource_id}) do
    Logger.debug("Got an error while downloading resource##{resource_id}: #{message}")
    :error
  end

  defp process_download({:ok, tmp_path, body}, %Resource{} = resource) do
    cellar_filename = upload_filename(resource, DateTime.utc_now())
    Transport.S3.upload_to_s3!(:history, body, cellar_filename)
    {:ok, tmp_path, cellar_filename}
  end

  def download_path(%Resource{id: resource_id}) do
    folder = System.tmp_dir!() |> Path.join("resource_#{resource_id}_gtfs_rt_validation")
    File.mkdir_p!(folder)
    Path.join([folder, to_string(resource_id)])
  end

  def gtfs_rt_result_path(%Resource{format: format} = resource) when is_gtfs_rt(format) do
    # https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#output
    "#{download_path(resource)}.results.json"
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
  defp remove_file(path), do: File.rm(path)
end
