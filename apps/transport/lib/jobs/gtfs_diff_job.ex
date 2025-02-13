defmodule Transport.Jobs.GTFSDiff do
  @moduledoc """
  Job in charge of computing a diff between two GTFS files
  """
  use Oban.Worker, max_attempts: 1, queue: :on_demand_validation

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "gtfs_file_name_1" => gtfs_file_name_1,
            "gtfs_file_name_2" => gtfs_file_name_2,
            "gtfs_original_file_name_1" => gtfs_original_file_name_1,
            "gtfs_original_file_name_2" => gtfs_original_file_name_2,
            "bucket" => bucket,
            "locale" => locale
          }
        } = job
      ) do
    Oban.Notifier.notify(Oban, :gossip, %{started: job.id})

    {:ok, unzip_1} = Transport.Unzip.S3.get_unzip(gtfs_file_name_1, bucket)
    {:ok, unzip_2} = Transport.Unzip.S3.get_unzip(gtfs_file_name_2, bucket)

    notify = fn log_msg ->
      Oban.Notifier.notify(Oban, :gossip, %{
        running: job.id,
        log: log_msg
      })
    end

    diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, notify, locale)

    diff_file_name = "gtfs-diff-#{DateTime.utc_now() |> DateTime.to_unix()}.csv"
    filepath = System.tmp_dir!() |> Path.join(diff_file_name)

    try do
      Transport.GTFSDiff.dump_diff(diff, filepath)
      Transport.S3.stream_to_s3!(:gtfs_diff, filepath, diff_file_name, acl: :public_read)

      Oban.Notifier.notify(Oban, :gossip, %{
        complete: job.id,
        diff_file_url: Transport.S3.permanent_url(:gtfs_diff, diff_file_name),
        gtfs_original_file_name_1: gtfs_original_file_name_1,
        gtfs_original_file_name_2: gtfs_original_file_name_2
      })
    after
      File.rm(filepath)
    end

    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_1)
    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_2)
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(job_timeout_sec())

  # 30 minutes, in seconds
  def job_timeout_sec, do: 30 * 60
end
