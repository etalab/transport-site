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
      insert(:resource_metadata, resource_id: resource.id, inserted_at: DateTime.utc_now() |> DateTime.add(-3, :day))

      assert resource_last_metadata_from_today(resource.id) == nil
    end

    test "there is one" do
      resource = insert(:resource)
      # most recent metadata for today
      metadata = insert(:resource_metadata, resource_id: resource.id, inserted_at: DateTime.utc_now())
      # metadata for today, but older
      insert(:resource_metadata, resource_id: resource.id, inserted_at: DateTime.utc_now() |> DateTime.add(-1, :minute))

      assert resource_last_metadata_from_today(resource.id) == metadata
    end
  end

  describe "resource freshness computation" do
    test "up to date GTFS resource" do
      %{resource: resource} = insert_up_to_date_resource_and_friends()
      assert resource_freshness(resource) == 1.0
    end

    test "outdated GTFS resource" do
      %{resource: resource} = insert_outdated_resource_and_friends()
      assert resource_freshness(resource) == 0.0
    end

    test "GTFS resource without metadata" do
      resource = insert(:resource, format: "GTFS")
      assert resource_freshness(resource) == nil
    end

    test "up to date GBFS resource" do
      resource = insert(:resource, format: "gbfs")
      insert(:resource_metadata, resource_id: resource.id, metadata: %{"feed_timestamp_delay" => 10})
      assert resource_freshness(resource) == 1.0
    end

    test "outdated GBFS resource" do
      resource = insert(:resource, format: "gbfs")
      insert(:resource_metadata, resource_id: resource.id, metadata: %{"feed_timestamp_delay" => 1000})
      assert resource_freshness(resource) == 0.0
    end

    test "GBFS resource without metadata for today" do
      resource = insert(:resource, format: "gbfs")

      insert(:resource_metadata,
        resource_id: resource.id,
        metadata: %{"feed_timestamp_delay" => 0},
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert resource_freshness(resource) == nil
    end
  end

  describe "current dataset freshness" do
    test "2 resources with freshness" do
      # dataset, with 1 GTFS resource
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()

      # we add a GTFS realtime resource to the dataset
      resource = insert(:resource, format: "gtfs-rt", dataset_id: dataset.id, is_community_resource: false)
      insert(:resource_metadata, resource_id: resource.id, metadata: %{"feed_timestamp_delay" => 1000})

      assert current_dataset_freshness(dataset.id) == 0.5
    end

    test "2 resources, but only one with freshness" do
      # dataset, with 1 outdated GTFS resource
      %{dataset: dataset} = insert_outdated_resource_and_friends()

      # we add a GTFS realtime resource to the dataset, but no metadata
      insert(:resource, format: "gtfs-rt", dataset_id: dataset.id, is_community_resource: false)

      # average freshness for only 1 resource with freshness information available
      assert current_dataset_freshness(dataset.id) == 0.0
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
      assert %{id: _id, topic: "freshness", score: 0.55, timestamp: timestamp} = score

      # we force refresh the score computation
      # it should use yesterday's score again
      {:ok, score} = save_dataset_freshness_score(dataset.id)
      assert %{id: _id, topic: "freshness", score: 0.55, timestamp: timestamp} = score
    end
  end
end
