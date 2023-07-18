defmodule Transport.Test.Transport.Jobs.DatasetQualityScoreTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Transport.Jobs.{DatasetAvailabilityScore, DatasetFreshnessScore, DatasetQualityScore}

  doctest Transport.Jobs.DatasetQualityScore, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "resource last today metadata" do
    test "there is none" do
      resource = insert(:resource)

      insert(:resource_metadata,
        resource_id: resource.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-3, :day)
      )

      assert resource_last_metadata_from_today(resource.id) == nil
    end

    test "there is one" do
      resource = insert(:resource)
      # most recent metadata for today
      metadata = insert(:resource_metadata, resource_id: resource.id, inserted_at: DateTime.utc_now())

      # metadata for today, but older
      insert(:resource_metadata,
        resource_id: resource.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :minute)
      )

      assert resource_last_metadata_from_today(resource.id) == metadata
    end
  end

  describe "resource freshness computation" do
    test "up to date GTFS resource" do
      %{resource: resource = %{id: resource_id}, resource_metadata: %{id: metadata_id, inserted_at: inserted_at}} =
        insert_up_to_date_resource_and_friends()

      assert %{
               format: "GTFS",
               freshness: 1.0,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: ^resource_id,
               metadata_id: ^metadata_id,
               metadata_inserted_at: ^inserted_at
             } = resource_freshness(resource)
    end

    test "outdated GTFS resource" do
      %{resource: resource} = insert_outdated_resource_and_friends()

      assert %{
               format: "GTFS",
               freshness: 0.0,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: _
             } = resource_freshness(resource)
    end

    test "future GTFS resource" do
      # insert a GTFS with validity dates in the future
      %{resource: resource} = insert_resource_and_friends(Date.utc_today() |> Date.add(365), [])

      assert %{
               format: "GTFS",
               freshness: nil,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: _
             } = resource_freshness(resource)
    end

    test "GTFS resource without metadata" do
      resource = insert(:resource, format: "GTFS")

      assert %{format: "GTFS", freshness: nil, raw_measure: nil, resource_id: _} = resource_freshness(resource)
    end

    test "GTFS with empty metadata" do
      resource = insert(:resource, format: "GTFS")
      resource_history = insert(:resource_history, resource_id: resource.id)

      validation =
        insert(:multi_validation,
          validator: Transport.Validators.GTFSTransport.validator_name(),
          resource_history_id: resource_history.id
        )

      insert(:resource_metadata,
        multi_validation_id: validation.id,
        metadata: %{"start_date" => nil, "end_date" => nil}
      )

      assert %{format: "GTFS", freshness: nil, raw_measure: nil, resource_id: _} = resource_freshness(resource)
    end

    test "up to date GBFS resource" do
      resource = %{id: resource_id} = insert(:resource, format: "gbfs")

      %{id: metadata_id, inserted_at: inserted_at} =
        insert(:resource_metadata,
          resource_id: resource.id,
          metadata: %{"feed_timestamp_delay" => 10}
        )

      assert %{
               format: "gbfs",
               freshness: 1.0,
               raw_measure: 10,
               resource_id: ^resource_id,
               metadata_id: ^metadata_id,
               metadata_inserted_at: ^inserted_at
             } = resource_freshness(resource)
    end

    test "outdated GBFS resource" do
      resource = insert(:resource, format: "gbfs")

      insert(:resource_metadata,
        resource_id: resource.id,
        metadata: %{"feed_timestamp_delay" => 1000}
      )

      assert %{format: "gbfs", freshness: 0.0, raw_measure: 1000, resource_id: _} = resource_freshness(resource)
    end

    test "GBFS resource without metadata for today" do
      resource = insert(:resource, format: "gbfs")

      insert(:resource_metadata,
        resource_id: resource.id,
        metadata: %{"feed_timestamp_delay" => 0},
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert %{format: "gbfs", freshness: nil, raw_measure: nil, resource_id: _} = resource_freshness(resource)
    end

    test "up to date gtfs-register_test() resource" do
      resource = %{id: resource_id} = insert(:resource, format: "gtfs-rt")

      %{id: metadata_id, inserted_at: inserted_at} =
        insert(:resource_metadata,
          resource_id: resource.id,
          metadata: %{"feed_timestamp_delay" => 10}
        )

      assert %{
               format: "gtfs-rt",
               freshness: 1.0,
               raw_measure: 10,
               resource_id: ^resource_id,
               metadata_id: ^metadata_id,
               metadata_inserted_at: ^inserted_at
             } = resource_freshness(resource)
    end
  end

  describe "resource_availability" do
    test "with no unavailabilites" do
      resource = insert(:resource)

      assert %{
               availability: 1.0,
               raw_measure: nil,
               resource_id: resource.id
             } == resource_availability(resource)
    end

    test "with an ongoing unavailability" do
      resource = insert(:resource)
      insert(:resource_unavailability, start: hours_ago(2), resource: resource)

      assert %{
               availability: 0.0,
               raw_measure: (22 / 24 * 100) |> Float.floor(1),
               resource_id: resource.id
             } == resource_availability(resource)
    end

    test "with a past availability" do
      resource = insert(:resource)
      insert(:resource_unavailability, start: hours_ago(48), end: hours_ago(23), resource: resource)

      assert %{
               availability: 0.5,
               raw_measure: (23 / 24 * 100) |> Float.floor(1),
               resource_id: resource.id
             } == resource_availability(resource)
    end
  end

  describe "current dataset availability" do
    test "2 resources with availability at 100%" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false)

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id},
                   %{availability: 1.0, raw_measure: nil, resource_id: r2.id}
                 ]
               },
               score: 1.0
             } == current_dataset_availability(dataset.id)
    end

    test "2 resources, one down for a long time" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false)
      insert(:resource_unavailability, resource: r2, start: hours_ago(25))

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id},
                   %{availability: 0.0, raw_measure: 0, resource_id: r2.id}
                 ]
               },
               score: 0.0
             } == current_dataset_availability(dataset.id)
    end

    test "2 resources, one down for a short period" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false)
      insert(:resource_unavailability, resource: r2, start: hours_ago(1))

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id},
                   %{availability: 0.5, raw_measure: (23 / 24 * 100) |> Float.floor(1), resource_id: r2.id}
                 ]
               },
               score: 0.75
             } == current_dataset_availability(dataset.id)
    end
  end

  describe "current dataset freshness" do
    test "2 resources with freshness" do
      # dataset, with 1 GTFS resource
      %{dataset: dataset, resource: %{id: resource_id}} = insert_up_to_date_resource_and_friends()

      # we add a GTFS realtime resource to the dataset
      %{id: resource_id_2} = insert(:resource, format: "gtfs-rt", dataset_id: dataset.id, is_community_resource: false)

      insert(:resource_metadata,
        resource_id: resource_id_2,
        metadata: %{"feed_timestamp_delay" => 1000}
      )

      assert %{
               score: 0.5,
               details: %{
                 resources: [
                   %{
                     format: "GTFS",
                     freshness: 1.0,
                     raw_measure: %{end_date: end_date, start_date: start_date},
                     resource_id: ^resource_id
                   },
                   %{
                     format: "gtfs-rt",
                     freshness: 0.0,
                     raw_measure: 1000,
                     resource_id: ^resource_id_2
                   }
                 ]
               }
             } = current_dataset_freshness(dataset.id)

      today = Date.utc_today()
      assert Date.diff(today, start_date) > 0 and Date.diff(end_date, today) > 0
    end

    test "2 resources, but only one with freshness" do
      # dataset, with 1 outdated GTFS resource
      %{dataset: dataset, resource: %{id: resource_id}} = insert_outdated_resource_and_friends()

      # we add a GTFS realtime resource to the dataset, but no metadata
      insert(:resource, format: "gtfs-rt", dataset_id: dataset.id, is_community_resource: false)

      # average freshness for only 1 resource with freshness information available
      assert %{
               score: 0.0,
               details: %{
                 resources: [
                   %{
                     format: "GTFS",
                     freshness: 0.0,
                     raw_measure: %{end_date: _, start_date: _},
                     resource_id: ^resource_id
                   },
                   %{
                     format: "gtfs-rt",
                     freshness: nil,
                     raw_measure: nil,
                     resource_id: _
                   }
                 ]
               }
             } = current_dataset_freshness(dataset.id)
    end
  end

  describe "last_dataset_score" do
    test "fetches the latest non-nil score for yesterday" do
      dataset = insert(:dataset, is_active: true)
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day)
      yesterday_after = yesterday |> DateTime.add(5, :second)

      insert(:dataset_score, dataset: dataset, topic: :availability, score: 0.5, timestamp: yesterday)
      insert(:dataset_score, dataset: dataset, topic: :availability, score: 0.75, timestamp: yesterday_after)
      insert(:dataset_score, dataset: dataset, topic: :freshness, score: 1.0, timestamp: yesterday)
      insert(:dataset_score, dataset: dataset, topic: :freshness, score: nil, timestamp: yesterday_after)

      assert %DB.DatasetScore{score: 0.75, topic: :availability} = last_dataset_score(dataset.id, :availability)
      assert %DB.DatasetScore{score: 1.0, topic: :freshness} = last_dataset_score(dataset.id, :freshness)
    end

    test "does not use scores if they are more than 7-day old" do
      dataset = insert(:dataset, is_active: true)

      insert(:dataset_score,
        dataset: dataset,
        topic: :availability,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-8, :day)
      )

      assert is_nil(last_dataset_score(dataset.id, :availability))
      assert is_nil(last_dataset_score(dataset.id, :freshness))
    end
  end

  describe "save_availability_score" do
    test "computes availability from yesterday and today" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)

      # we save an availability score for yesterday
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :availability,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # a score for another topic
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      # expected score is 0.5 * 0.9 + 1. * (1. - 0.9) = 0.55
      # see exp_smoothing() function
      assert {
               :ok,
               %DB.DatasetScore{id: _id, topic: :availability, score: 0.55, timestamp: timestamp, details: details}
             } = save_availability_score(dataset.id)

      assert DateTime.diff(timestamp, DateTime.utc_now(), :second) < 3
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3

      assert %{
               previous_score: 0.5,
               resources: [
                 %{
                   availability: 1.0,
                   resource_id: r1.id,
                   raw_measure: nil
                 }
               ]
             } == details
    end
  end

  describe "save dataset average freshness" do
    test "compute freshness from yesterday and today" do
      %{dataset: dataset, resource: %{id: resource_id}, resource_metadata: %{id: metadata_id}} =
        insert_up_to_date_resource_and_friends()

      # we save a freshness score for yesterday
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # another irrelevant score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :availability,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      {:ok, score} = save_freshness_score(dataset.id)

      # expected score is 0.5 * 0.9 + 1. * (1. - 0.9)
      # see exp_smoothing() function
      assert %{id: _id, topic: :freshness, score: 0.55, timestamp: timestamp, details: details} = score

      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3

      assert %{
               previous_score: 0.5,
               resources: [
                 %{
                   format: "GTFS",
                   freshness: 1.0,
                   resource_id: ^resource_id,
                   raw_measure: %{start_date: start_date, end_date: end_date},
                   metadata_id: ^metadata_id
                 }
               ]
             } = details

      assert Date.diff(Date.utc_today(), start_date) > 0 and Date.diff(end_date, Date.utc_today()) > 0
    end

    test "no score yesterday" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # an irrelevant score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :availability,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1

      {:ok, score} = save_freshness_score(dataset.id)

      # expected score is todays's score (no existing history)
      assert %{id: _id, topic: :freshness, score: 1.0, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2
    end

    test "no score at all" do
      dataset = insert(:dataset)
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 0

      {:ok, score} = save_freshness_score(dataset.id)

      # expected score is nil
      assert %{id: _id, topic: :freshness, score: nil, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1
    end

    test "new score is computed with last non nil score" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # last score is nil
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: nil,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # but existing score before
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-2, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      {:ok, score} = save_freshness_score(dataset.id)

      # score is computed with today's freshness and last non nil score.
      assert %{id: _id, topic: :freshness, score: 0.55, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3
    end

    test "new score is computed with last non nil score, unless it is too old" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # old existing score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-8, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1

      {:ok, score} = save_freshness_score(dataset.id)

      # score is computed from scratch, previous score is not used
      assert %{id: _id, topic: :freshness, score: 1.0, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2
    end

    test "last score timestamp is not today" do
      # if a score is for some reason computed many times in one day
      # we don't want to massively change the score
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()

      # yesterday's score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      {:ok, score} = save_freshness_score(dataset.id)
      # score is computed with yesterday's score
      assert %{id: id1, topic: :freshness, score: 0.55, timestamp: _timestamp} = score

      # we force refresh the score computation
      # it should use yesterday's score again
      {:ok, score} = save_freshness_score(dataset.id)
      assert %{id: id2, topic: :freshness, score: 0.55, timestamp: _timestamp} = score
      assert id2 > id1
    end

    test "dataset without scorable resource" do
      dataset = insert(:dataset, is_active: true)
      %{id: resource_id} = insert(:resource, dataset_id: dataset.id, format: "csv", is_community_resource: false)

      {:ok, score} = save_freshness_score(dataset.id)

      assert %{
               topic: :freshness,
               score: nil,
               details: %{previous_score: nil, resources: [%{resource_id: ^resource_id, format: "csv", freshness: nil}]}
             } = score
    end
  end

  test "resource_ids_with_unavailabilities" do
    r1 = insert(:resource)
    r2 = insert(:resource)
    r3 = insert(:resource)
    insert(:resource_unavailability, resource: r1, start: hours_ago(5))
    insert(:resource_unavailability, resource: r2, start: hours_ago(48), end: hours_ago(30))
    insert(:resource_unavailability, resource: r3, start: hours_ago(5), end: hours_ago(2))
    insert(:resource_unavailability, resource: r3, start: hours_ago(30), end: hours_ago(10))

    assert [r1.id, r3.id] |> Enum.sort() == resource_ids_with_unavailabilities() |> Enum.sort()
  end

  describe "DatasetQualityScore" do
    test "job saves multiple topics for a dataset" do
      assert DB.DatasetScore |> DB.Repo.all() |> Enum.empty?()
      %{dataset: %DB.Dataset{id: dataset_id} = dataset} = insert_up_to_date_resource_and_friends()
      assert :ok == perform_job(Transport.Jobs.DatasetQualityScore, %{"dataset_id" => dataset.id})

      assert [
               %DB.DatasetScore{
                 dataset_id: ^dataset_id,
                 topic: :freshness,
                 score: 1.0,
                 details: %{
                   "previous_score" => nil,
                   "resources" => [
                     %{
                       "format" => "GTFS",
                       "freshness" => 1.0,
                       "raw_measure" => %{"end_date" => _, "start_date" => _},
                       "resource_id" => _
                     }
                   ]
                 }
               },
               %DB.DatasetScore{
                 dataset_id: ^dataset_id,
                 topic: :availability,
                 score: 1.0,
                 details: %{
                   "previous_score" => nil,
                   "resources" => [%{"availability" => 1.0, "raw_measure" => nil, "resource_id" => _}]
                 }
               }
             ] = DB.DatasetScore |> DB.Repo.all()
    end
  end

  describe "DatasetQualityScoreDispatcher" do
    test "jobs are enqueued" do
      dataset_1 = insert(:dataset)
      dataset_2 = insert(:dataset)
      dataset_3 = insert(:dataset, is_active: false)

      assert :ok == perform_job(Transport.Jobs.DatasetQualityScoreDispatcher, %{})

      assert_enqueued(
        worker: Transport.Jobs.DatasetQualityScore,
        args: %{"dataset_id" => dataset_1.id}
      )

      assert_enqueued(
        worker: Transport.Jobs.DatasetQualityScore,
        args: %{"dataset_id" => dataset_2.id}
      )

      refute_enqueued(
        worker: Transport.Jobs.DatasetQualityScore,
        args: %{"dataset_id" => dataset_3.id}
      )
    end
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours, :hour) |> DateTime.truncate(:second)
  end
end
