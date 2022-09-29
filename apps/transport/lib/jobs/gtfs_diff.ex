defmodule Transport.Jobs.GtfsDiff do
  @moduledoc """
  Job in charge of computing a diff between two GTFS files
  """
  use Oban.Worker, max_attempts: 1
  # require Logger
  # import Ecto.Query
  # alias DB.{Dataset, Repo, Resource}

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"gtfs_file_name_1" => gtfs_file_name_1, "gtfs_file_name_2" => gtfs_file_name_2, "bucket" => bucket}
        } = job
      ) do
    {:ok, unzip_1} = Transport.Unzip.S3.get_unzip(gtfs_file_name_1, bucket)
    {:ok, unzip_2} = Transport.Unzip.S3.get_unzip(gtfs_file_name_2, bucket)
    diff = Transport.Beta.GTFS.diff(unzip_1, unzip_2)

    diff_file_name = "gtfs-diff-#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

    Transport.S3.upload_to_s3!(
      :gtfs_diff,
      diff |> Transport.Beta.GTFS.dump_diff(),
      diff_file_name
    )

    Oban.Notifier.notify(Oban, :gossip, %{
      complete: job.id,
      diff_file_url: Transport.S3.permanent_url(:gtfs_diff, diff_file_name)
    })

    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_1)
    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_2)
    :ok
  end
end
