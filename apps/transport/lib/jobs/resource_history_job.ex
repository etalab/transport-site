defmodule Transport.Jobs.ResourceHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceHistoryJob`
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"], max_attempts: 5
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
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"]
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @payload_version 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"datagouv_id" => datagouv_id}}) do
    Logger.info("Running ResourceHistoryJob for #{datagouv_id}")
    resource = Resource |> where([r], r.datagouv_id == ^datagouv_id) |> Repo.one!()

    {resource_path, headers, body} = download_resource(resource)

    upload_filename = upload_to_s3!(resource, body)

    zip_metadata = Transport.ZipMetaDataExtractor.extract!(resource_path)

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
    remove_file!(resource_path)

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  defp store_resource_history!(%Resource{datagouv_id: datagouv_id}, payload) do
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
    "#{resource.datagouv_id}/#{resource.datagouv_id}.#{d.year}#{d.month}#{d.minute}.#{microsecond}.zip"
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
