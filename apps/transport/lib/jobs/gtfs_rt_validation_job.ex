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
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource, ResourceHistory}
  require Logger

  @validator_path "/usr/local/bin/gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    dataset =
      Dataset
      |> preload(:resources)
      |> where([d], d.id == ^dataset_id)
      |> Repo.one!()

    gtfs = dataset.resources |> Enum.find(&(Resource.is_gtfs?(&1) and Resource.valid_and_available?(&1)))
    gtfs_rts = dataset.resources |> Enum.filter(&(Resource.is_gtfs_rt?(&1) and &1.is_available))

    if Enum.empty?(gtfs_rts) do
      raise "Should have gtfs-rt resources for Dataset #{dataset_id}"
    end

    gtfs_path = download_path(gtfs)
    save_latest_gtfs(latest_resource_history(gtfs), gtfs_path)

    try do
      gtfs_rts
      |> snapshot_gtfs_rts()
      |> Enum.reject(&(elem(&1, 1) == :error))
      |> Enum.each(fn res ->
        binary_path = "java"
        {_resource, {:ok, gtfs_rt_path, cellar_filename}} = res

        # See https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#batch-processing
        args = ["-jar", @validator_path, "-gtfs", gtfs_path, "-gtfsRealtimePath", Path.dirname(gtfs_rt_path)]
        Transport.RamboLauncher.run(binary_path, args, log: true)
      end)
    after
      gtfs_rts |> Enum.each(&(&1 |> download_path() |> remove_file()))
      gtfs_rts |> Enum.each(&(&1 |> gtfs_rt_result_path() |> remove_file()))
      remove_file(gtfs_path)
      File.rmdir(Path.dirname(gtfs_path))
    end

    :ok
  end

  defp latest_resource_history(%Resource{datagouv_id: datagouv_id, format: "GTFS"}) do
    ResourceHistory
    |> where([r], r.datagouv_id == ^datagouv_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  def snapshot_gtfs_rts(gtfs_rts) do
    gtfs_rts |> Enum.map(&{&1, snapshot_gtfs_rt(&1)})
  end

  def snapshot_gtfs_rt(%Resource{} = resource) do
    resource |> download_resource(download_path(resource)) |> process_download(resource)
  end

  def upload_filename(%Resource{datagouv_id: datagouv_id}, %DateTime{} = dt) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{datagouv_id}/#{datagouv_id}.#{time}.bin"
  end

  defp save_latest_gtfs(%ResourceHistory{payload: %{"permanent_url" => url}}, tmp_path) do
    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)
    File.write!(tmp_path, body)
  end

  defp download_resource(%Resource{datagouv_id: datagouv_id, url: url}, tmp_path) do
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

  defp download_path(%Resource{datagouv_id: datagouv_id}) do
    folder = System.tmp_dir!() |> Path.join("resource_#{datagouv_id}_gtfs_rt_validation")
    File.mkdir_p!(folder)
    Path.join([folder, datagouv_id])
  end

  defp gtfs_rt_result_path(%Resource{} = resource) do
    # https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#output
    "#{download_path(resource)}.results.json"
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
  defp remove_file(path), do: File.rm(path)
end
