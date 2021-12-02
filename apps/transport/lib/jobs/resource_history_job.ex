defmodule Transport.Jobs.ResourceHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceHistoryJob`
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"], max_attempts: 5
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(_job) do
    Transport.S3.create_bucket_if_needed!(:history)

    datagouv_ids = resources_to_historise()

    Logger.debug("Dispatching #{Enum.count(datagouv_ids)} ResourceHistoryJob jobs")

    datagouv_ids
    |> Enum.map(fn datagouv_id ->
      %{datagouv_id: datagouv_id} |> Transport.Jobs.ResourceHistoryJob.new()
    end)
    |> Oban.insert_all()

    :ok
  end

  def resources_to_historise do
    # FIX ME
    # Some datagouv_ids are duplicated for resources.
    # Since our ResourceHistoryJob assumes an uniqueness, ignore
    # those for the time being.
    # See https://github.com/etalab/transport-site/issues/1930
    duplicates =
      Resource
      |> where([r], not is_nil(r.datagouv_id))
      |> group_by([r], r.datagouv_id)
      |> having([r], count(r.datagouv_id) > 1)
      |> select([r], r.datagouv_id)
      |> Repo.all()

    Resource
    |> where([r], not is_nil(r.url) and not is_nil(r.title) and not is_nil(r.datagouv_id))
    |> where([r], r.format == "GTFS" or r.format == "NeTEx")
    |> where([r], r.datagouv_id not in ^duplicates)
    |> where([r], not r.is_community_resource)
    |> select([r], r.datagouv_id)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.ResourceHistoryJob do
  @moduledoc """
  Job historicising a single resource
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5, fields: [:args, :queue, :worker]], tags: ["history"], max_attempts: 5
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"datagouv_id" => datagouv_id}}) do
    Logger.info("Running ResourceHistoryJob for #{datagouv_id}")
    resource = Resource |> where([r], r.datagouv_id == ^datagouv_id) |> Repo.one!()

    path = download_path(resource)

    try do
      resource |> download_resource(path) |> process_download(resource)
    after
      remove_file(path)
    end

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(2)

  defp process_download({:error, message}, %Resource{datagouv_id: datagouv_id}) do
    # Good opportunity to add a :telemetry event
    # Consider storing in our database that the resource
    # was not available.
    Logger.debug("Got an error while downloading #{datagouv_id}: #{message}")
  end

  defp process_download({:ok, resource_path, headers, body}, %Resource{datagouv_id: datagouv_id} = resource) do
    download_datetime = DateTime.utc_now()
    zip_metadata = Transport.ZipMetaDataExtractor.extract!(resource_path)

    case should_store_resource?(resource, zip_metadata) do
      true ->
        filename = upload_filename(resource, download_datetime)

        data = %{
          download_datetime: download_datetime,
          uuid: Ecto.UUID.generate(),
          zip_metadata: zip_metadata,
          http_headers: headers,
          resource_metadata: resource.metadata,
          filename: filename,
          permanent_url: Transport.S3.permanent_url(:history, filename),
          format: resource.format,
          filenames: zip_metadata |> Enum.map(& &1.file_name),
          total_uncompressed_size: zip_metadata |> Enum.map(& &1.uncompressed_size) |> Enum.sum(),
          total_compressed_size: zip_metadata |> Enum.map(& &1.compressed_size) |> Enum.sum()
        }

        upload_to_s3!(body, filename)
        store_resource_history!(resource, data)

      false ->
        # Good opportunity to add a :telemetry event
        Logger.debug("skipping historization for #{datagouv_id} because resource did not change")
    end
  end

  @doc """
  Determine if we would historicise a payload now.

  We should historicise a resource if:
  - we never historicised it
  - the latest ResourceHistory payload is different than the current state
  """
  def should_store_resource?(%Resource{datagouv_id: datagouv_id}, zip_metadata) do
    history =
      DB.ResourceHistory
      |> where([r], r.datagouv_id == ^datagouv_id)
      |> order_by(desc: :inserted_at)
      |> limit(1)
      |> DB.Repo.one()

    if is_nil(history), do: true, else: not is_same_resource?(history, zip_metadata)
  end

  @doc """
  Determines if a ZIP metadata payload is the same that was stored in
  the latest resource_history's row in the database by comparing sha256
  hashes for all files in the ZIP.
  """
  def is_same_resource?(%DB.ResourceHistory{payload: payload}, zip_metadata) do
    MapSet.equal?(set_of_sha256(payload["zip_metadata"]), set_of_sha256(zip_metadata))
  end

  def set_of_sha256(items), do: MapSet.new(items |> Enum.map(fn m -> Map.get(m, "sha256") || Map.get(m, :sha256) end))

  defp store_resource_history!(%Resource{datagouv_id: datagouv_id}, payload) do
    Logger.debug("Saving ResourceHistory for #{datagouv_id}")

    %DB.ResourceHistory{datagouv_id: datagouv_id, payload: payload}
    |> DB.Repo.insert!()
  end

  defp download_path(%Resource{datagouv_id: datagouv_id}) do
    System.tmp_dir!() |> Path.join("resource_#{datagouv_id}_download")
  end

  defp download_resource(%Resource{datagouv_id: datagouv_id, url: url}, file_path) do
    case Unlock.HTTP.Client.impl().get!(url, []) do
      %{status: 200, body: body, headers: headers} ->
        Logger.debug("Saving resource #{datagouv_id} to #{file_path}")
        File.write!(file_path, body)
        relevant_headers = headers |> Enum.into(%{}) |> Map.take(relevant_http_headers())
        {:ok, file_path, relevant_headers, body}

      %{status: status} ->
        {:error, "Got a non 200 status: #{status}"}

      %Finch.Error{reason: reason} ->
        {:error, "Got an error: #{reason}"}
    end
  end

  defp remove_file(path), do: File.rm(path)

  defp upload_to_s3!(body, path) do
    Logger.debug("Uploading resource to #{path}")

    :history
    |> Transport.S3.bucket_name()
    |> ExAws.S3.put_object(
      path,
      body,
      acl: "public-read"
    )
    |> Transport.Wrapper.ExAWS.impl().request!()
  end

  def upload_filename(%Resource{datagouv_id: datagouv_id} = resource, %DateTime{} = dt) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{datagouv_id}/#{datagouv_id}.#{time}.zip"
  end

  defp relevant_http_headers do
    [
      "content-disposition",
      "content-encoding",
      "content-length",
      "content-type",
      "etag",
      "expires",
      "if-modified-since",
      "last-modified"
    ]
  end
end
