defmodule Transport.Test.Transport.Jobs.MigrateHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Mox

  alias Transport.Jobs.{MigrateHistoryDispatcherJob, MigrateHistoryJob}
  alias Transport.Test.S3TestUtils

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  describe "MigrateHistoryDispatcherJob" do
    test "it works" do
      datagouv_id = "5c34c93f8b4c4104b817fb3a"
      expected_href = "https://dataset-#{datagouv_id}.cellar-c2.services.clever-cloud.com/Fichiers_GTFS_20201118T000001"
      already_backed_up_href = "https://example.com/already_backuped"

      dataset = insert(:dataset, datagouv_id: datagouv_id)
      resource = insert(:resource, datagouv_id: "foo")

      insert(:resource_history,
        payload: %{from_old_system: true, old_href: already_backed_up_href},
        datagouv_id: resource.datagouv_id
      )

      S3TestUtils.s3_mock_list_buckets(["dataset-#{datagouv_id}", "dataset-foo"])

      Transport.History.Fetcher.Mock
      |> expect(:history_resources, fn arg ->
        assert dataset.id == arg.id

        [
          %{
            href: expected_href,
            is_current: false,
            last_modified: "2020-11-18T00:00:01.953Z",
            metadata: %{
              "content-hash" => "1111dfda713942722c5497f561e9f2f3d4caa23e01f3c26c0a5252b7e7261fcd",
              "end" => "2021-07-04",
              "format" => "GTFS",
              "start" => "2020-11-01",
              "title" => "Fichiers_GTFS",
              "updated-at" => "2020-11-17T10:28:05.852000",
              "url" => "https://example.com/Fichiers_GTFS_20201118T000001"
            },
            name: "Fichiers_GTFS_20201118T000001"
          },
          # Should be ignored because the original URL is on demo-static
          %{href: "", metadata: %{"url" => "https://demo-static.data.gouv.fr/gtfs"}},
          # Should be ignored because it has already been backed up
          %{href: already_backed_up_href, metadata: %{"url" => "https://example.com/file"}}
        ]
      end)

      assert :ok == perform_job(MigrateHistoryDispatcherJob, %{})
      assert [%Oban.Job{args: %{"href" => ^expected_href}}] = all_enqueued(worker: MigrateHistoryJob)
    end
  end
end
