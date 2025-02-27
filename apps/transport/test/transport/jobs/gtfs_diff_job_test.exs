defmodule Transport.Jobs.GTFSDiffTest do
  use ExUnit.Case, async: true
  alias Transport.Jobs.GTFSDiff
  alias Transport.Test.S3TestUtils
  use Oban.Testing, repo: DB.Repo
  import Mox

  setup do
    # We need sandboxing to be disabled for Oban notifications to be persisted
    # in the test database and therefore propagated to the test case.
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo, sandbox: false)
  end

  setup :verify_on_exit!

  @base_file "test/fixture/files/gtfs_diff/gtfs.zip"
  @modified_file "test/fixture/files/gtfs_diff/gtfs_modified_rows.zip"

  describe "with GTFS in the gtfs_diff S3 bucket" do
    test "process job" do
      with_notifications(fn ->
        base_gtfs_object = "base-#{Ecto.UUID.generate()}.zip"
        modified_gtfs_object = "modified-#{Ecto.UUID.generate()}.zip"

        expect_get_from_bucket(base_gtfs_object, @base_file)
        expect_get_from_bucket(modified_gtfs_object, @modified_file)

        expect_csv_streamed_to_s3()

        expect_delete_from_bucket(base_gtfs_object)
        expect_delete_from_bucket(modified_gtfs_object)

        enqueue_job(%{"gtfs_object_1" => base_gtfs_object, "gtfs_object_2" => modified_gtfs_object})

        expect_various_notifications()
      end)
    end
  end

  describe "with external URLs" do
    test "process job" do
      with_notifications(fn ->
        base_gtfs_url = "http://localhost/gtfs/base-#{Ecto.UUID.generate()}.zip"
        modified_gtfs_url = "http://localhost/gtfs/modified-#{Ecto.UUID.generate()}.zip"

        expect_get_from_url(base_gtfs_url, @base_file)
        expect_get_from_url(modified_gtfs_url, @modified_file)

        expect_csv_streamed_to_s3()

        enqueue_job(%{"gtfs_url_1" => base_gtfs_url, "gtfs_url_2" => modified_gtfs_url})

        expect_various_notifications()
      end)
    end
  end

  defp expect_get_from_bucket(object, file) do
    Transport.Unzip.S3.Mock
    |> expect(:get_unzip, fn ^object, bucket_name ->
      assert bucket_name == "transport-data-gouv-fr-gtfs-diff-test"

      file
      |> Unzip.LocalFile.open()
      |> Unzip.new()
    end)
  end

  defp expect_delete_from_bucket(object) do
    Transport.Test.S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:gtfs_diff), object)
  end

  defp expect_get_from_url(url, file) do
    Transport.Req.impl()
    |> expect(:get, fn ^url, options ->
      stream_copy(file, options[:into])

      {:ok, %{status: 200}}
    end)
  end

  defp stream_copy(file, into_stream) do
    File.stream!(file)
    |> Stream.into(into_stream)
    |> Stream.run()
  end

  defp with_notifications(func) do
    Oban.Notifier.listen(:gossip)
    func.()
  after
    Oban.Notifier.unlisten(:gossip)
  end

  defp expect_various_notifications do
    job_id = expect_start_notification()
    expect_running_notification(job_id, "Calcul des différences pour <code>agency.txt</code>")
    expect_running_notification(job_id, "Calcul des différences pour <code>calendar.txt</code>")
    expect_running_notification(job_id, "Calcul des différences pour <code>routes.txt</code>")
    expect_running_notification(job_id, "Calcul des différences pour <code>stops.txt</code>")
    expect_running_notification(job_id, "Calcul des différences pour <code>trips.txt</code>")
    expect_completion_notification(job_id)
  end

  defp expect_start_notification do
    assert_receive {:notification, :gossip, %{"started" => job_id}}

    job_id
  end

  defp expect_running_notification(job_id, msg) do
    assert_receive {:notification, :gossip, %{"running" => ^job_id, "log" => ^msg}}
  end

  defp expect_completion_notification(job_id) do
    assert_receive {:notification, :gossip,
                    %{
                      "complete" => ^job_id,
                      "diff_file_url" => _,
                      "gtfs_original_file_name_1" => "base.zip",
                      "gtfs_original_file_name_2" => "modified.zip"
                    }}
  end

  defp enqueue_job(args) do
    base_args = %{
      "gtfs_original_file_name_1" => "base.zip",
      "gtfs_original_file_name_2" => "modified.zip",
      "profile" => "core",
      "locale" => "fr"
    }

    assert :ok == perform_job(GTFSDiff, Map.merge(base_args, args))
  end

  defp expect_csv_streamed_to_s3 do
    S3TestUtils.s3_mock_stream_file(start_path: "gtfs-diff", bucket: Transport.S3.bucket_name(:gtfs_diff))
  end
end
