require Logger

Logger.info("Starting...")

import Ecto.Query

# Useful notes:
# - we could look at "last up to date" to ensure we only have fresh data in database
# - use gtfs_to_db once downloaded
# - look at Transport.Jobs.BNLCToGeoData and Transport.Jobs.BaseGeoData.import_replace_data

# create a local S3 copy (via MinIO) of each latest ResourceHistory file so
# that the production database dump can be used locally with a matching local S3 file
records =
  DB.Dataset.base_query()
  |> DB.Resource.join_dataset_with_resource()
  |> DB.ResourceHistory.join_resource_with_latest_resource_history()
  |> where([resource: r], r.format == "GTFS")
  |> select([resource_history: rh], rh)
  |> DB.Repo.all()
  |> Enum.drop(1)
  |> Enum.take(1)
  |> Enum.each(fn rh ->
    # create local minio bucket, if needed
    minio_folder = Path.expand("~/data")
    bucket_name = Transport.S3.bucket_name(:history)
    base_path = Path.join(minio_folder, bucket_name)
    unless File.exists?(base_path), do: File.mkdir_p!(base_path)

    # simple check based on file presence on disk
    file_path = Path.join(base_path, rh.payload["permanent_url"])

    if File.exists?(file_path) do
      Logger.info("File already downloaded, skipping...")
    else
      %HTTPoison.Response{status_code: 200, body: body} =
        Transport.Shared.Wrapper.HTTPoison.impl().get!(rh.payload["permanent_url"])

      Transport.S3.upload_to_s3!(:history, body, rh.payload["filename"])
    end

    Logger.info("Trying streaming...")
    data = Transport.Jobs.GtfsToDB.file_stream(rh.id, "stops.txt")
    Logger.info("OK")
  end)
