defmodule DB.DatasetScoreTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  doctest DB.DatasetScore, import: true

  describe "save dataset score" do
    test "some fields are mandatory" do
      changeset = %DB.DatasetScore{} |> DB.DatasetScore.changeset(%{})

      assert %Ecto.Changeset{
               valid?: false,
               errors: [
                 dataset_id: {"can't be blank", [validation: :required]},
                 topic: {"can't be blank", [validation: :required]},
                 timestamp: {"can't be blank", [validation: :required]}
               ]
             } = changeset
    end

    test "score has constraints" do
      changeset =
        %DB.DatasetScore{}
        |> DB.DatasetScore.changeset(%{dataset_id: 1, topic: :freshness, score: 2.0, timestamp: DateTime.utc_now()})

      assert %Ecto.Changeset{
               valid?: false,
               errors: [
                 score: {"must be between 0.0 and 1.0", []}
               ]
             } = changeset
    end

    test "topic is an enum" do
      changeset =
        %DB.DatasetScore{}
        |> DB.DatasetScore.changeset(%{dataset_id: 1, topic: :foo, score: 0.5, timestamp: DateTime.utc_now()})

      assert %Ecto.Changeset{
               valid?: false,
               errors: [
                 topic: {"is invalid", _}
               ]
             } = changeset
    end
  end

  test "get latest score" do
    dataset = insert(:dataset)
    other_dataset = insert(:dataset)

    # old
    insert(:dataset_score,
      dataset_id: dataset.id,
      timestamp: DateTime.utc_now() |> DateTime.add(-1, :day),
      score: 1.0,
      topic: :freshness
    )

    # the expected result
    score =
      insert(:dataset_score,
        dataset_id: dataset.id,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :hour),
        score: 0.55,
        topic: :freshness
      )

    # bad dataset
    insert(:dataset_score, dataset_id: other_dataset.id, timestamp: DateTime.utc_now(), score: 1.0, topic: :freshness)

    # bad topic
    insert(:dataset_score, dataset_id: dataset.id, timestamp: DateTime.utc_now(), score: 1.0, topic: :availability)

    assert score == DB.DatasetScore.get_latest(dataset, :freshness)
  end

  test "get unexisting latest score" do
    assert %DB.Dataset{id: 123_456} |> DB.DatasetScore.get_latest(:freshness) |> is_nil()
  end

  test "get_latest_scores" do
    dataset = insert(:dataset)
    other_dataset = insert(:dataset)

    # old
    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now() |> DateTime.add(-1, :day),
      score: 1.0,
      topic: :freshness
    )

    # the expected results
    freshness_score =
      insert(:dataset_score,
        dataset_id: dataset.id,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :hour),
        score: 0.55,
        topic: :freshness
      )

    availability_score =
      insert(:dataset_score, dataset_id: dataset.id, timestamp: DateTime.utc_now(), score: 1.0, topic: :availability)

    # other dataset
    insert(:dataset_score, dataset: other_dataset, timestamp: DateTime.utc_now(), score: 1.0, topic: :freshness)

    assert %{freshness: freshness_score} == DB.DatasetScore.get_latest_scores(dataset, [:freshness])

    assert %{freshness: freshness_score, availability: availability_score} ==
             DB.DatasetScore.get_latest_scores(dataset, [:freshness, :availability])

    assert %{} == DB.DatasetScore.get_latest_scores(%DB.Dataset{id: 123_456}, [:freshness, :availability])
  end

  test "scores_over_last_days" do
    dataset = insert(:dataset)
    other_dataset = insert(:dataset)

    # other dataset
    insert(:dataset_score, dataset: other_dataset, timestamp: DateTime.utc_now(), score: 1.0, topic: :freshness)

    [{-3, 0.75}, {-2, 0.5}, {-1, 0.75}, {0, 1}]
    |> Enum.each(fn {days_delta, score} ->
      insert(:dataset_score,
        dataset: dataset,
        timestamp: DateTime.utc_now() |> DateTime.add(days_delta, :day),
        score: score,
        topic: :freshness
      )

      insert(:dataset_score,
        dataset: dataset,
        timestamp: DateTime.utc_now() |> DateTime.add(days_delta, :day),
        score: score - 0.25,
        topic: :availability
      )
    end)

    # should be ignored, not the latest point for today
    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now() |> DateTime.add(-5, :minute),
      score: 0,
      topic: :freshness
    )

    # a nil value
    insert(:dataset_score,
      dataset: dataset,
      timestamp: DateTime.utc_now(),
      score: nil,
      topic: :compliance
    )

    assert [
             %DB.DatasetScore{topic: :freshness, score: 0.5},
             %DB.DatasetScore{topic: :availability, score: 0.25},
             %DB.DatasetScore{topic: :freshness, score: 0.75},
             %DB.DatasetScore{topic: :availability, score: 0.5},
             %DB.DatasetScore{topic: :freshness, score: 1.0},
             %DB.DatasetScore{topic: :availability, score: 0.75},
             %DB.DatasetScore{topic: :compliance, score: nil}
           ] = DB.DatasetScore.scores_over_last_days(dataset, 2)
  end
end
