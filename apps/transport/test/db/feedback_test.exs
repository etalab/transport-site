defmodule DB.FeedbackTest do
  use ExUnit.Case, async: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save and read a feedback with encrypted email" do
    %DB.Feedback{}
    |> DB.Feedback.changeset(%{
      rating: :like,
      explanation: "<love>Awesome map!</love>",
      feature: :"gtfs-stops",
      email: "Malotru@example.coM   "
    })
    |> DB.Repo.insert()

    assert %DB.Feedback{email: "malotru@example.com", explanation: "Awesome map!"} =
             DB.Feedback |> Ecto.Query.last() |> DB.Repo.one!()
  end
end
