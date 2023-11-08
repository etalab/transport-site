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
            "bucket" => bucket
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

    diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, notify)

    diff_file_name = "gtfs-diff-#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

    Transport.S3.upload_to_s3!(
      :gtfs_diff,
      diff |> Transport.GTFSDiff.dump_diff(),
      diff_file_name,
      acl: :public_read
    )

    Oban.Notifier.notify(Oban, :gossip, %{
      complete: job.id,
      diff_file_url: Transport.S3.permanent_url(:gtfs_diff, diff_file_name)
    })

    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_1)
    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_2)
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(job_timeout_sec())

  # 5 minutes timeout
  def job_timeout_sec, do: 300
end
