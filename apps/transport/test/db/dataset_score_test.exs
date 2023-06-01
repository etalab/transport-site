defmodule DB.DatasetScoreTest do
  use ExUnit.Case

  describe "save dataset score" do
    test "some fields are mandatory" do
      changeset = %DB.DatasetScore{} |> DB.DatasetScore.changeset(%{})

      assert %{
               valid?: false,
               errors: [
                 dataset_id: {"can't be blank", [validation: :required]},
                 topic: {"can't be blank", [validation: :required]},
                 score: {"can't be blank", [validation: :required]},
                 timestamp: {"can't be blank", [validation: :required]}
               ]
             } = changeset
    end

    test "score has constraints" do
      changeset =
        %DB.DatasetScore{}
        |> DB.DatasetScore.changeset(%{dataset_id: 1, topic: "freshness", score: 2.0, timestamp: DateTime.utc_now()})

      assert %{
               valid?: false,
               errors: [
                 score: {"must be beetween 0.0 and 1.0", []}
               ]
             } = changeset
    end
  end
end
