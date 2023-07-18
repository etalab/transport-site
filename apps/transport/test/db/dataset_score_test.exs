defmodule DB.DatasetScoreTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

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

    assert score == DB.DatasetScore.get_latest(dataset, "freshness")
  end

  test "get unexisting latest score" do
    assert %DB.Dataset{id: 123_456} |> DB.DatasetScore.get_latest("freshness") |> is_nil()
  end
end
