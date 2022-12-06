require Logger

Logger.info("Starting...")

import Ecto.Query

# Useful notes:
# - we could look at "last up to date" to ensure we only have fresh data in database
# - use gtfs_to_db once downloaded
# - look at Transport.Jobs.BNLCToGeoData and Transport.Jobs.BaseGeoData.import_replace_data

defmodule Tooling do
  # for each active dataset, grab all resources with a resource history.
  def query() do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> where([resource: r], r.format == "GTFS")
    |> select([resource_history: rh], rh)
  end
end

defmodule SyncS3LatestResourceHistory do
  def sync!(minio_folder) do
    Tooling.query()
    |> DB.Repo.all()
    # TODO: task sync max concurrency (this is slow)
    |> Enum.each(fn rh ->
      # create local minio bucket, if needed
      bucket_name = Transport.S3.bucket_name(:history)
      base_path = Path.join(minio_folder, bucket_name)
      unless File.exists?(base_path), do: File.mkdir_p!(base_path)

      # simple check based on file presence on disk
      file_path = Path.join(base_path, rh.payload["filename"])

      # TODO: replace by head request
      if File.exists?(file_path) do
        Logger.info("File already downloaded, skipping...")
      else
        Logger.info("Downloading file...")
        Logger.info(file_path)

        %HTTPoison.Response{status_code: 200, body: body} =
          Transport.Shared.Wrapper.HTTPoison.impl().get!(rh.payload["permanent_url"])

        Transport.S3.upload_to_s3!(:history, body, rh.payload["filename"])
      end
    end)
  end
end

defmodule IngestResourceHistoryGTFSData do
  def process(rh) do
    try do
      data_import_id = Transport.Jobs.GtfsToDB.import_gtfs_from_resource_history(rh.id, :stops)
      {:ok, data_import_id}
    rescue
      e ->
        # a quick way to satisfy our curiosity with regard to the errors
        # later it will be better to keep a proper consolidated log so that
        # we can inspect programmatically the outcome
        IO.inspect(rh |> Map.take([:resource_id, :id, :datagouv_id]) |> Map.put(:error, e))
        {:error, e}
    end
  end

  def ingest!() do
    Tooling.query()
    # |> limit(50)
    |> DB.Repo.all()
    |> Enum.map(fn rh ->
      Logger.info("Trying streaming...")
      process(rh)
    end)
  end
end

# # create a local S3 copy (via MinIO) of each latest ResourceHistory file so
# # that the production database dump can be used locally with a matching local S3 file
SyncS3LatestResourceHistory.sync!(Path.expand("~/data"))

IngestResourceHistoryGTFSData.ingest!()
|> IO.inspect(IEx.inspect_opts())

# TODO: handle deletion of duplicate (DELETE USING, CTE, or what is done in BLNC import)
