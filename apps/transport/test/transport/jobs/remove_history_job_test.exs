defmodule Transport.Test.Transport.Jobs.RemoveHistoryJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.RemoveHistoryJob
  alias Transport.Test.S3TestUtils

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "enqueues jobs when deleting by dataset type" do
    %DB.Dataset{id: d1_id} = insert(:dataset, type: "vehicles-sharing")
    %DB.Dataset{id: d2_id} = insert(:dataset, type: "vehicles-sharing")
    dataset_3 = insert(:dataset, type: "public-transit")

    assert :ok == perform_job(RemoveHistoryJob, %{"dataset_type" => "vehicles-sharing"})

    assert MapSet.new([d1_id, d2_id]) ==
             [worker: RemoveHistoryJob]
             |> all_enqueued()
             |> Enum.map(fn %Oban.Job{args: %{"dataset_id" => dataset_id}} -> dataset_id end)
             |> MapSet.new()

    refute DB.Dataset.should_skip_history?(dataset_3)
    assert :ok == perform_job(RemoveHistoryJob, %{"dataset_type" => "public-transit"})

    assert Enum.count(all_enqueued(worker: RemoveHistoryJob)) == 2
  end

  test "cannot delete history rows for wrong dataset type" do
    dataset = insert(:dataset, type: "public-transit")

    refute DB.Dataset.should_skip_history?(dataset)
    assert {:cancel, _} = perform_job(RemoveHistoryJob, %{"dataset_id" => dataset.id})
  end

  test "marks for deletion relevant rows when deleting by dataset_id" do
    %{id: dataset_id} = dataset = insert(:dataset, type: "vehicles-sharing")
    resource = insert(:resource, dataset_id: dataset.id)

    rh1 = insert(:resource_history, resource_id: resource.id, payload: %{"dataset_id" => dataset.id})
    rh2 = insert(:resource_history, resource_id: resource.id, payload: %{"dataset_id" => dataset.id})

    assert DB.Dataset.should_skip_history?(dataset)
    assert :ok == perform_job(RemoveHistoryJob, %{"dataset_id" => dataset.id})

    rh1_payload = Map.put(rh1.payload, "mark_for_deletion", true)
    rh2_payload = Map.put(rh2.payload, "mark_for_deletion", true)

    assert [%DB.ResourceHistory{payload: ^rh1_payload}, %DB.ResourceHistory{payload: ^rh2_payload}] =
             DB.Repo.reload([rh1, rh2])

    assert [%Oban.Job{args: %{"dataset_id" => ^dataset_id, "action" => "remove"}}] =
             all_enqueued(worker: RemoveHistoryJob)
  end

  test "marks for deletion relevant rows when deleting by schema_name and days_limit" do
    resource = insert(:resource, dataset: insert(:dataset, type: "charging-stations"))

    rh1 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{"schema_name" => "etalab/schema-irve-dynamique"},
        inserted_at: DateTime.utc_now() |> DateTime.add(-5, :day)
      )

    rh2 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{"schema_name" => "etalab/schema-irve-dynamique"},
        inserted_at: DateTime.utc_now() |> DateTime.add(-5, :day)
      )

    # Should not be marked for deletion because it's too recent
    rh3 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{"schema_name" => "etalab/schema-irve-dynamique"},
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

    assert :ok == perform_job(RemoveHistoryJob, %{"schema_name" => "etalab/schema-irve-dynamique", "days_limit" => 3})

    rh1_payload = Map.put(rh1.payload, "mark_for_deletion", true)
    rh2_payload = Map.put(rh2.payload, "mark_for_deletion", true)
    rh3_payload = rh3.payload

    assert [
             %DB.ResourceHistory{payload: ^rh1_payload},
             %DB.ResourceHistory{payload: ^rh2_payload},
             %DB.ResourceHistory{payload: ^rh3_payload}
           ] = DB.Repo.reload([rh1, rh2, rh3])

    assert [%Oban.Job{args: job_args}] = all_enqueued(worker: RemoveHistoryJob)
    assert job_args == %{"action" => "remove"}
  end

  test "removes rows and deletes objects for a given dataset_id" do
    public_transit_dataset = insert(:dataset, type: "public-transit")
    public_transit_resource = insert(:resource, dataset_id: public_transit_dataset.id)

    # Should not be deleted because it does not have `mark_for_deletion` and
    # does not belong to the dataset for which we will enqueue a job
    public_transit_resource_history =
      insert(:resource_history,
        resource_id: public_transit_resource.id,
        payload: %{"filename" => Ecto.UUID.generate(), "dataset_id" => public_transit_dataset.id}
      )

    %{id: dataset_id} = dataset = insert(:dataset, type: "vehicles-sharing")
    resource = insert(:resource, dataset_id: dataset.id)

    rh1 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{
          "filename" => rh1_filename = Ecto.UUID.generate(),
          "dataset_id" => dataset.id,
          "mark_for_deletion" => true
        }
      )

    rh2 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{
          "filename" => rh2_filename = Ecto.UUID.generate(),
          "dataset_id" => dataset.id,
          "mark_for_deletion" => true
        }
      )

    S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), rh1_filename)
    S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), rh2_filename)

    assert :ok == perform_job(RemoveHistoryJob, %{"dataset_id" => dataset.id, "action" => "remove"})

    assert [nil, nil, %DB.ResourceHistory{}] = DB.Repo.reload([rh1, rh2, public_transit_resource_history])

    assert [%Oban.Job{args: %{"dataset_id" => ^dataset_id, "action" => "remove"}, scheduled_at: scheduled_at}] =
             all_enqueued(worker: RemoveHistoryJob)

    refute is_nil(scheduled_at)
  end

  test "removes rows and deletes objects when marked for deletion" do
    public_transit_dataset = insert(:dataset, type: "public-transit")
    public_transit_resource = insert(:resource, dataset_id: public_transit_dataset.id)

    # Should not be deleted because it does not have `mark_for_deletion`
    public_transit_resource_history =
      insert(:resource_history,
        resource_id: public_transit_resource.id,
        payload: %{"filename" => Ecto.UUID.generate(), "dataset_id" => public_transit_dataset.id}
      )

    resource = insert(:resource, dataset: insert(:dataset, type: "charging-stations"))

    rh1 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{
          "filename" => rh1_filename = Ecto.UUID.generate(),
          "schema_name" => "etalab/schema-irve-dynamique",
          "mark_for_deletion" => true
        }
      )

    rh2 =
      insert(:resource_history,
        resource_id: resource.id,
        payload: %{
          "filename" => rh2_filename = Ecto.UUID.generate(),
          "schema_name" => "etalab/schema-irve-dynamique",
          "mark_for_deletion" => true
        }
      )

    S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), rh1_filename)
    S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), rh2_filename)

    assert :ok == perform_job(RemoveHistoryJob, %{"action" => "remove"})

    assert [nil, nil, %DB.ResourceHistory{}] = DB.Repo.reload([rh1, rh2, public_transit_resource_history])

    assert [%Oban.Job{args: job_args, scheduled_at: scheduled_at}] = all_enqueued(worker: RemoveHistoryJob)
    assert job_args == %{"action" => "remove"}
    refute is_nil(scheduled_at)
  end

  test "does not enqueue a job when there is nothing left" do
    assert :ok == perform_job(RemoveHistoryJob, %{"dataset_id" => 42, "action" => "remove"})
    assert [] == all_enqueued(worker: RemoveHistoryJob)
  end
end
