defmodule Transport.Jobs.GtfsDiff do
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
    diff_file_name =
      compute_diff(%{
        "gtfs_file_name_1" => gtfs_file_name_1,
        "gtfs_file_name_2" => gtfs_file_name_2,
        "bucket" => bucket
      })

    gtfs_diff = save_to_db(diff_file_name, [gtfs_file_name_1, gtfs_file_name_2])
    notify(job, gtfs_diff.id)

    :ok
  end

  def perform(%Oban.Job{args: %{"gtfs_files" => gtfs_files}} = job) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    [gtfs_file_name_2, gtfs_file_name_1] =
      gtfs_files
      |> Enum.map(fn %{"url" => url} ->
        {:ok, %{status_code: 200, body: body}} = http_client.get(url, [], follow_redirect: true)
        file_name = Ecto.UUID.generate()
        filepath = file_name |> tmp_filepath()
        filepath |> File.write!(body)
        upload_to_s3(filepath, file_name)
        file_name
      end)

    diff_file_name =
      compute_diff(%{
        "gtfs_file_name_1" => gtfs_file_name_1,
        "gtfs_file_name_2" => gtfs_file_name_2,
        "bucket" => Transport.S3.bucket_name(:gtfs_diff)
      })

    gtfs_diff = save_to_db(diff_file_name, gtfs_files)
    notify(job, gtfs_diff.id)

    :ok
  end

  def save_to_db(diff_file_name, [input_1, input_2]) do
    %DB.GTFSDiff{result_url: Transport.S3.permanent_url(:gtfs_diff, diff_file_name), input_1: input_1, input_2: input_2}
    |> DB.Repo.insert!()
  end

  def notify(job, gtfs_diff_id) do
    Oban.Notifier.notify(Oban, :gossip, %{
      complete: job.id,
      gtfs_diff_id: gtfs_diff_id
    })
  end

  def compute_diff(%{
        "gtfs_file_name_1" => gtfs_file_name_1,
        "gtfs_file_name_2" => gtfs_file_name_2,
        "bucket" => bucket
      }) do
    {:ok, unzip_1} = Transport.Unzip.S3.get_unzip(gtfs_file_name_1, bucket)
    {:ok, unzip_2} = Transport.Unzip.S3.get_unzip(gtfs_file_name_2, bucket)
    diff = Transport.Beta.GTFS.diff(unzip_1, unzip_2)

    diff_file_name = "gtfs-diff-#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

    Transport.S3.upload_to_s3!(
      :gtfs_diff,
      diff |> Transport.Beta.GTFS.dump_diff(),
      diff_file_name
    )

    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_1)
    Transport.S3.delete_object!(:gtfs_diff, gtfs_file_name_2)

    diff_file_name
  end

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:gtfs_diff, File.read!(file_path), path)
  end

  def tmp_filepath(filename), do: Path.join(System.tmp_dir!(), filename)
end
