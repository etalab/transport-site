defmodule Transport.Test.Transport.Jobs.DatasetQualityScoreTest do
  use ExUnit.Case, async: true
  doctest Transport.Jobs.DatasetQualityScore, import: true
  import DB.Factory
  import Transport.Jobs.DatasetQualityScore

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
      %{resource: resource} = insert_up_to_date_resource_and_friends()

      assert %{
               format: "GTFS",
               freshness: 1.0,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: _
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
      resource = insert(:resource, format: "gbfs")

      insert(:resource_metadata,
        resource_id: resource.id,
        metadata: %{"feed_timestamp_delay" => 10}
      )

      assert %{format: "gbfs", freshness: 1.0, raw_measure: 10, resource_id: _} = resource_freshness(resource)
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
               dataset_freshness: 0.5,
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
               dataset_freshness: 0.0,
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

  describe "save dataset average freshness" do
    test "compute freshness from yesterday and today" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # we save a freshness score for yesterday
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: "freshness",
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # another irrelevant score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: "fun",
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      {:ok, score} = save_dataset_freshness_score(dataset.id)

      # expected score is 0.5 * 0.9 + 1. * (1. - 0.9)
      # see exp_smoothing() function
      assert %{id: _id, topic: "freshness", score: 0.55, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3
    end

    test "no score yesterday" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # an irrelevant score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: "fun",
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1

      {:ok, score} = save_dataset_freshness_score(dataset.id)

      # expected score is todays's score (no existing history)
      assert %{id: _id, topic: "freshness", score: 1.0, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2
    end

    test "no score at all" do
      dataset = insert(:dataset)
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 0

      {:ok, score} = save_dataset_freshness_score(dataset.id)

      # expected score is nil
      assert %{id: _id, topic: "freshness", score: nil, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1
    end

    test "new score is computed with last non nil score" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # last score is nil
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: "freshness",
        score: nil,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # but existing score before
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: "freshness",
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-2, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      {:ok, score} = save_dataset_freshness_score(dataset.id)

      # score is computed with today's freshness and last non nil score.
      assert %{id: _id, topic: "freshness", score: 0.55, timestamp: timestamp} = score
      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3
    end

    test "last score timestamp is not today" do
      # if a score is for some reason computed many times in one day
      # we don't want to massively change the score
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()

      # yesterday's score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: "freshness",
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      {:ok, score} = save_dataset_freshness_score(dataset.id)
      # score is computed with yesterday's score
      assert %{id: id1, topic: "freshness", score: 0.55, timestamp: _timestamp} = score

      # we force refresh the score computation
      # it should use yesterday's score again
      {:ok, score} = save_dataset_freshness_score(dataset.id)
      assert %{id: id2, topic: "freshness", score: 0.55, timestamp: _timestamp} = score
      assert id2 > id1
    end
  end
end
