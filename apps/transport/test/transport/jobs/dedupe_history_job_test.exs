defmodule Transport.Test.Transport.Jobs.DedupeHistoryJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  alias DB.{Repo, ResourceHistory}
  alias Transport.Jobs.{DedupeHistoryDispatcherJob, DedupeHistoryJob}
  alias Transport.Test.S3TestUtils

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @datagouv_id "foo"

  describe "DedupeHistoryDispatcherJob" do
    test "it works" do
      insert(:resource_history, payload: %{}, datagouv_id: "foo")
      insert(:resource_history, payload: %{}, datagouv_id: "foo")
      insert(:resource_history, payload: %{}, datagouv_id: "bar")

      assert :ok == perform_job(DedupeHistoryDispatcherJob, %{})

      assert [
               %Oban.Job{args: %{"datagouv_id" => "foo"}},
               %Oban.Job{args: %{"datagouv_id" => "bar"}}
             ] = all_enqueued(worker: DedupeHistoryJob)
    end
  end

  describe "is_same?" do
    test "same objects" do
      assert DedupeHistoryJob.is_same?(resource_history_with_shas(["a", "b"]), resource_history_with_shas(["b", "a"]))
    end

    test "different objects" do
      refute DedupeHistoryJob.is_same?(resource_history_with_shas(["a"]), resource_history_with_shas(["b"]))

      refute DedupeHistoryJob.is_same?(resource_history_with_shas(["a"]), resource_history_with_shas(["a", "b"]))
    end
  end

  describe "DedupeHistoryJob" do
    test "does nothing" do
      insert_resource_history_with_shas(["a"], ~U[2020-11-17 10:28:05Z])
      insert_resource_history_with_shas(["b"], ~U[2020-11-18 10:28:05Z])

      assert 2 == count_resource_history()

      perform_job(DedupeHistoryJob, %{"datagouv_id" => @datagouv_id})

      assert 2 == count_resource_history()
    end

    test "removes duplicates" do
      insert_resource_history_with_shas(["a"], ~U[2020-11-17 10:28:05Z])
      to_remove1 = insert_resource_history_with_shas(["a"], ~U[2020-11-18 10:28:05Z])
      insert_resource_history_with_shas(["b"], ~U[2020-11-18 10:28:05Z])
      insert_resource_history_with_shas(["c"], ~U[2020-11-19 10:28:05Z])
      to_remove2 = insert_resource_history_with_shas(["c"], ~U[2020-11-20 10:28:05Z])
      insert_resource_history_with_shas(["d"], ~U[2020-11-21 10:28:05Z])

      S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), to_remove1.payload["filename"])
      S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), to_remove2.payload["filename"])

      assert 6 == count_resource_history()

      perform_job(DedupeHistoryJob, %{"datagouv_id" => @datagouv_id})

      assert 4 == count_resource_history()
      assert is_nil(Repo.get(ResourceHistory, to_remove1.id))
      assert is_nil(Repo.get(ResourceHistory, to_remove2.id))
    end

    test "scopes by datagouv_id" do
      insert_resource_history_with_shas(["a"], ~U[2020-11-18 10:28:05Z], "foo")
      insert_resource_history_with_shas(["a"], ~U[2020-11-19 10:28:05Z], "bar")

      assert 2 == count_resource_history()

      perform_job(DedupeHistoryJob, %{"datagouv_id" => "foo"})
      perform_job(DedupeHistoryJob, %{"datagouv_id" => "bar"})

      assert 2 == count_resource_history()
    end
  end

  defp insert_resource_history_with_shas(shas, inserted_at, datagouv_id \\ nil) do
    insert(:resource_history,
      payload: %{"zip_metadata" => shas |> Enum.map(&%{"sha256" => &1}), "filename" => "#{inserted_at}.zip"},
      inserted_at: inserted_at,
      datagouv_id: datagouv_id || @datagouv_id
    )
  end

  defp resource_history_with_shas(shas) do
    %ResourceHistory{payload: %{"zip_metadata" => shas |> Enum.map(&%{"sha256" => &1})}}
  end

  defp count_resource_history do
    Repo.one!(from(r in ResourceHistory, select: count()))
  end
end
