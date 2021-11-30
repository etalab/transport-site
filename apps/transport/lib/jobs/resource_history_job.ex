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

    duplicates =
      Resource
      |> where([r], not is_nil(r.datagouv_id))
      |> group_by([r], r.datagouv_id)
      |> having([r], count(r.datagouv_id) > 1)
      |> select([r], r.datagouv_id)
      |> Repo.all()

    datagouv_ids =
      Resource
      |> where([r], not is_nil(r.url) and not is_nil(r.title) and not is_nil(r.datagouv_id))
      |> where([r], r.format == "GTFS" or r.format == "NeTEx")
      |> where([r], r.datagouv_id not in ^duplicates)
      |> where([r], not r.is_community_resource)
      |> select([r], r.datagouv_id)
      |> Repo.all()

    Logger.debug("Dispatching #{Enum.count(datagouv_ids)} ResourceHistoryJob jobs")

    datagouv_ids
    |> Enum.each(fn datagouv_id ->
      %{datagouv_id: datagouv_id}
      |> Transport.Jobs.ResourceHistoryJob.new()
      |> Oban.insert()
    end)

    :ok
  end
end

defmodule Transport.Jobs.ResourceHistoryJob do
  @moduledoc """
  Job historicising a single resource
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"], max_attempts: 5
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @payload_version 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"datagouv_id" => datagouv_id}}) do
    Logger.info("Running ResourceHistoryJob for #{datagouv_id}")
    resource = Resource |> where([r], r.datagouv_id == ^datagouv_id) |> Repo.one!()

    {resource_path, headers, body} = download_resource(resource)

    zip_metadata = Transport.ZipMetaDataExtractor.extract!(resource_path)

    case should_store_resource?(resource, zip_metadata) do
      true ->
        upload_filename = upload_to_s3!(resource, body)

        data = %{
          zip_metadata: zip_metadata,
          http_headers: headers,
          resource_metadata: resource.metadata,
          upload_filename: upload_filename,
          format: resource.format,
          filenames: zip_metadata |> Enum.map(& &1.file_name),
          total_uncompressed_size: zip_metadata |> Enum.map(& &1.uncompressed_size) |> Enum.sum(),
          total_compressed_size: zip_metadata |> Enum.map(& &1.compressed_size) |> Enum.sum()
        }

        store_resource_history!(resource, data)

      false ->
        Logger.debug("skipping historization for #{datagouv_id} because resource did not change")
        :ok
    end

    remove_file!(resource_path)

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @doc """
  Determine if we would historicise a payload now.

  We should historicise a resource if:
  - we never historicised it
  - the latest ResourceHistory payload is different than the current state
  """
  def should_store_resource?(%Resource{datagouv_id: datagouv_id}, zip_metadata) do
    if @payload_version != 1 do
      raise RuntimeError, "may need to update logic if we have multiple versions"
    end

    history =
      DB.ResourceHistory
      |> where([r], r.version == 1)
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

    %DB.ResourceHistory{datagouv_id: datagouv_id, payload: payload, version: @payload_version}
    |> DB.Repo.insert!()
  end

  defp download_resource(%Resource{datagouv_id: datagouv_id, url: url}) do
    file_path = System.tmp_dir!() |> Path.join("resource_#{datagouv_id}_download")

    %{status: 200, body: body, headers: headers} = Unlock.HTTP.Client.impl().get!(url, [])
    Logger.debug("Saving resource #{datagouv_id} to #{file_path}")
    File.write!(file_path, body)

    relevant_headers = headers |> Enum.into(%{}) |> Map.take(relevant_http_headers())

    {file_path, relevant_headers, body}
  end

  defp remove_file!(path), do: File.rm!(path)

  defp upload_to_s3!(%Resource{} = resource, body) do
    filename = upload_filename(resource)

    Logger.debug("Uploading resource to #{filename}")

    :history
    |> Transport.S3.bucket_name()
    |> ExAws.S3.put_object(
      filename,
      body,
      acl: "public-read"
    )
    |> Transport.Wrapper.ExAWS.impl().request!()

    filename
  end

  defp upload_filename(%Resource{} = resource) do
    d = DateTime.utc_now()
    {microsecond, _} = d.microsecond

    parts = [
      "#{d.year}#{d.month}#{d.day}",
      "#{d.hour}#{d.minute}",
      microsecond
    ]

    "#{resource.datagouv_id}/#{resource.datagouv_id}.#{parts |> Enum.join(".")}.zip"
  end

  defp relevant_http_headers do
    [
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
