defmodule Transport.Jobs.GTFSRTMultiValidationDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTMultiValidationJob`.
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_datasets()
    |> Enum.map(&(%{dataset_id: &1.id} |> Transport.Jobs.GTFSRTMultiValidationJob.new()))
    |> Oban.insert_all()

    :ok
  end

  def relevant_datasets do
    # relevant datasets are active datasets having a gtfs-rt and a single GTFS resource,
    # that is both available and up to date

    resources =
      DB.Resource.base_query()
      |> DB.ResourceHistory.join_resource_with_latest_resource_history()
      |> DB.MultiValidation.join_resource_history_with_latest_validation("GTFS transport-validator")
      |> DB.ResourceMetadata.join_validation_with_metadata()
      |> where([resource: r], r.format == "GTFS" and r.is_available)
      |> DB.ResourceMetadata.where_gtfs_up_to_date()
      |> select([resource: r], r.dataset_id)
      |> group_by([resource: r], r.dataset_id)
      |> having([resource: r], count(r.id) == 1)

    DB.Dataset.base_query()
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], r.format == "gtfs-rt" and r.is_available)
    |> where([d], d.id in subquery(resources))
    |> distinct(true)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTMultiValidationJob do
  @moduledoc """
  Job validating gtfs-rt resources and saving validation
  results.
  """
  use Oban.Worker, max_attempts: 5, tags: ["validation"]
  import Ecto.Query
  alias DB.{Repo, Resource, ResourceHistory}
  alias Transport.Validators.GTFSRT
  require Logger

  defguard is_gtfs_rt(format) when format in ["gtfs-rt", "gtfsrt"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    gtfs = up_to_date_gtfs_resources(dataset_id)

    gtfs_rts = gtfs_rt_resources(dataset_id)

    if Enum.empty?(gtfs_rts) do
      raise "Should have gtfs-rt resources for Dataset #{dataset_id}"
    end

    gtfs_path = download_path(gtfs)
    gtfs_resource_history = gtfs.resource_history |> Enum.at(0)
    download_latest_gtfs(gtfs_resource_history, gtfs_path)

    try do
      gtfs_rts
      |> snapshot_gtfs_rts()
      |> Enum.reject(&(elem(&1, 1) == :error))
      |> Enum.each(fn snapshot ->
        {rt_resource, {:ok, gtfs_rt_path, cellar_filename}} = snapshot

        _validator_return =
          with {:ok, _} <- GTFSRT.run_validator(gtfs_path, gtfs_rt_path),
               {:ok, report} <- rt_resource |> gtfs_rt_result_path() |> GTFSRT.convert_validator_report() do
            update_resource(
              rt_resource,
              GTFSRT.build_validation_details(gtfs_resource_history, report, cellar_filename),
              gtfs_path,
              gtfs_rt_path,
              gtfs_resource_history
            )
          else
            :error -> {:error, "Could not run validator. Please provide a GTFS and a GTFS-RT."}
            e -> e
          end

        # log_validation(validator_return, resource)
      end)
    after
      Logger.debug("Cleaning up temporary files")
      clean_gtfs_rts(gtfs_rts)
      clean_gtfs(gtfs_path)
    end

    :ok
  end

  def up_to_date_gtfs_resources(dataset_id) do
    Resource.base_query()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> DB.MultiValidation.join_resource_history_with_latest_validation("GTFS transport-validator")
    |> DB.ResourceMetadata.join_validation_with_metadata()
    |> where([resource: r], r.format == "GTFS" and r.is_available and r.dataset_id == ^dataset_id)
    |> DB.ResourceMetadata.where_gtfs_up_to_date()
    |> preload([resource_history: rh], resource_history: rh)
    |> limit(1)
    |> Repo.one()
  end

  def gtfs_rt_resources(dataset_id) do
    Resource.base_query()
    |> where([resource: r], r.format == "gtfs-rt" and r.is_available and r.dataset_id == ^dataset_id)
    |> Repo.all()
  end

  defp update_resource(
         %Resource{} = gtfs_rt_resource,
         validation_details,
         gtfs_path,
         gtfs_rt_path,
         gtfs_resource_history
       ) do
    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: GTFSRT.validator_name(),
      command: inspect(GTFSRT.command(gtfs_path, gtfs_rt_path)),
      result: validation_details,
      resource_id: gtfs_rt_resource.id,
      secondary_resource_history_id: gtfs_resource_history.id,
      max_error: Map.fetch!(validation_details, "max_severity")
    }
    |> DB.Repo.insert!()
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

  defp snapshot_gtfs_rts(gtfs_rts) do
    gtfs_rts |> Enum.map(&{&1, snapshot_gtfs_rt(&1)})
  end

  defp snapshot_gtfs_rt(%Resource{format: format} = resource) when is_gtfs_rt(format) do
    resource |> download_resource(download_path(resource)) |> process_download(resource)
  end

  defp upload_filename(%Resource{datagouv_id: datagouv_id, format: format}, %DateTime{} = dt) when is_gtfs_rt(format) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{datagouv_id}/#{datagouv_id}.#{time}.bin"
  end

  defp download_latest_gtfs(%ResourceHistory{payload: %{"permanent_url" => url, "format" => "GTFS"}}, tmp_path) do
    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)
    File.write!(tmp_path, body)
  end

  defp download_resource(%Resource{datagouv_id: datagouv_id, url: url, is_available: true, format: format}, tmp_path)
       when is_gtfs_rt(format) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("Saving resource #{datagouv_id} to #{tmp_path}")
        File.write!(tmp_path, body)
        {:ok, tmp_path, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "Got a non 200 status: #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Got an error: #{reason}"}
    end
  end

  defp process_download({:error, message}, %Resource{datagouv_id: datagouv_id}) do
    Logger.debug("Got an error while downloading #{datagouv_id}: #{message}")
    :error
  end

  defp process_download({:ok, tmp_path, body}, %Resource{} = resource) do
    cellar_filename = upload_filename(resource, DateTime.utc_now())
    Transport.S3.upload_to_s3!(:history, body, cellar_filename)
    {:ok, tmp_path, cellar_filename}
  end

  def download_path(%Resource{datagouv_id: datagouv_id}) do
    folder = System.tmp_dir!() |> Path.join("resource_#{datagouv_id}_gtfs_rt_validation")
    File.mkdir_p!(folder)
    Path.join([folder, datagouv_id])
  end

  def gtfs_rt_result_path(%Resource{format: format} = resource) when is_gtfs_rt(format) do
    # https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#output
    "#{download_path(resource)}.results.json"
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
  defp remove_file(path), do: File.rm(path)
end
