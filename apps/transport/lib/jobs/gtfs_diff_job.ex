defmodule Transport.Jobs.GTFSDiff do
  @moduledoc """
  Job in charge of computing a diff between two GTFS files
  """
  use Oban.Worker, max_attempts: 1, queue: :on_demand_validation

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    Oban.Notifier.notify(Oban, :gossip, %{started: job.id})

    case args do
      %{
        "gtfs_object_1" => gtfs_object_1,
        "gtfs_object_2" => gtfs_object_2,
        "gtfs_original_file_name_1" => gtfs_original_file_name_1,
        "gtfs_original_file_name_2" => gtfs_original_file_name_2
      } ->
        context = %{
          "gtfs_original_file_name_1" => gtfs_original_file_name_1,
          "gtfs_original_file_name_2" => gtfs_original_file_name_2
        }

        process_s3_objects(job.id, gtfs_object_1, gtfs_object_2, Map.merge(args, %{"context" => context}))

      %{"gtfs_url_1" => gtfs_url_1, "gtfs_url_2" => gtfs_url_2} ->
        context = %{
          "gtfs_url_1" => gtfs_url_1,
          "gtfs_url_2" => gtfs_url_2
        }

        process_urls(job.id, gtfs_url_1, gtfs_url_2, Map.merge(args, %{"context" => context}))
    end

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(job_timeout_sec())

  # 30 minutes, in seconds
  def job_timeout_sec, do: 30 * 60

  defp process_s3_objects(job_id, gtfs_object_1, gtfs_object_2, args) do
    bucket_name = Transport.S3.bucket_name(:gtfs_diff)

    {:ok, unzip_1} = Transport.Unzip.S3.impl().get_unzip(gtfs_object_1, bucket_name)
    {:ok, unzip_2} = Transport.Unzip.S3.impl().get_unzip(gtfs_object_2, bucket_name)

    process_diff(job_id, unzip_1, unzip_2, args)
  after
    Transport.S3.delete_object!(:gtfs_diff, gtfs_object_1)
    Transport.S3.delete_object!(:gtfs_diff, gtfs_object_2)
  end

  defp process_urls(job_id, gtfs_url_1, gtfs_url_2, args) do
    {:ok, file_1} = download_resource(gtfs_url_1)
    {:ok, file_2} = download_resource(gtfs_url_2)

    try do
      {:ok, unzip_1} = unzip_local(file_1)
      {:ok, unzip_2} = unzip_local(file_2)

      process_diff(job_id, unzip_1, unzip_2, args)
    after
      File.rm(file_1)
      File.rm(file_2)
    end
  end

  defp download_resource(url) do
    file_path = mk_tmp_file()
    file_stream = File.stream!(file_path)

    req_options = [compressed: false, decode_body: false, receive_timeout: 180_000, into: file_stream]

    case Transport.Req.impl().get(url, req_options) do
      {:ok, %{status: 200}} ->
        {:ok, file_path}

      {:ok, %{status: status_code}} ->
        # NOTE: the file is still on disk at this point
        {:error, "Got a non 200 status: #{status_code}"}

      {:error, error} ->
        {:error, "Got an error: #{error |> inspect}"}
    end
  end

  defp mk_tmp_file do
    System.tmp_dir!() |> Path.join(Ecto.UUID.generate())
  end

  defp unzip_local(file) do
    file |> Unzip.LocalFile.open() |> Unzip.new()
  end

  defp process_diff(job_id, unzip_1, unzip_2, %{
         "context" => context,
         "profile" => profile,
         "locale" => locale
       }) do
    notify = fn log_msg ->
      Oban.Notifier.notify(Oban, :gossip, %{
        running: job_id,
        log: log_msg
      })
    end

    diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, profile, notify, locale)

    diff_file_name = "gtfs-diff-#{DateTime.utc_now() |> DateTime.to_unix()}.csv"
    filepath = System.tmp_dir!() |> Path.join(diff_file_name)

    try do
      Transport.GTFSDiff.dump_diff(diff, filepath)
      Transport.S3.stream_to_s3!(:gtfs_diff, filepath, diff_file_name, acl: :public_read)

      Oban.Notifier.notify(Oban, :gossip, %{
        complete: job_id,
        diff_file_url: Transport.S3.permanent_url(:gtfs_diff, diff_file_name),
        context: context
      })
    after
      File.rm(filepath)
    end
  end
end
